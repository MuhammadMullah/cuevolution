# Data Model: Competitions Context (specs 006–009, tasks T064–T103)

Ash Framework check: `mix.exs` and `lib/` show no `ash`/`ash_phoenix`/`ash_postgres` deps and no `use Ash.Resource`. Standard Ecto applies.

Project conventions confirmed from existing code:
- `@primary_key {:id, :binary_id, autogenerate: true}` + `@foreign_key_type :binary_id` on every schema.
- `config/config.exs` sets `generators: [timestamp_type: :utc_datetime, binary_id: true]` — migrations use plain `timestamps()` (no `_usec`), so **do not** use `:utc_datetime_usec` here even though the skill's generic template suggests it. Follow the existing `utc_datetime` convention exactly.
- Forward-referencing FKs (mutually-dependent tables) are handled by adding a plain `:binary_id` column first, then a later migration does `modify :col, references(...), from: :binary_id` once the target table exists (see `players.team_id` → `teams`). This exact pattern is needed for `fixtures.result_id` → `match_results` (fixtures created in 5c, match_results in 5d).
- CHECK constraints ARE expressible in Ecto's migration DSL via `create constraint(table, name, check: "...")` — already used for `players.gender`, `notifications.channel/status`. **This is not "raw SQL migration escape-hatch" territory** — it's a first-class Ecto.Migration macro (compiles to `ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)`). The only place genuine raw SQL (`execute/1,2`) is needed in this whole design is the atomic capacity-update in `Ecto.Multi` (application code, not a migration) and possibly the `least()/greatest()` functional unique index, which Ecto's `unique_index/3` macro *can* express directly by passing raw expression strings as index columns (also already precedented by `players_lower_username_index` using `"lower(username)"`).
- Category alignment: `Player.gender` uses plain string field + CHECK `IN ('male','female')`. Competitions' "category" concept must be `IN ('male','female','team')` — modeled the same way (plain `:string` + CHECK), not `Ecto.Enum`, to match existing convention rather than introduce a new pattern.
- Partial/functional unique index precedent: `venues_region_lower_name_active_index` (`unique_index(:venues, [:region_id, "lower(name)"], where: "active = true")`) is the direct precedent for both T077's `least/greatest` duplicate-pairing index and T065's composite unique index.

---

## Entity-relationship summary

```
Stage 1--* StageCapacityConfig
Stage 1--* StageParticipation *--1 Region
StageParticipation *--1 Player (nullable)   \_ exactly one set (CHECK)
StageParticipation *--1 Team (nullable)     /
Stage 1--* Group 1--* GroupMembership *--1 StageParticipation
Group 1--1 KnockoutBracket (Regional only)
Stage 1--* Round --* Fixture
Fixture *--1 StageParticipation (participant_a)
Fixture *--1 StageParticipation (participant_b)
Fixture *--1 Venue
Fixture 1--1 MatchResult (nullable until played; result_id is the forward FK)
MatchResult *--1 StageParticipation (winner)
MatchResult 1--* MatchFrame (Team category only)
MatchFrame *--1 Player (home), *--1 Player (away), *--1 Player (frame winner)
MatchResult 1--* CuevoPointsEntry
CuevoPointsEntry *--1 StageParticipation (participant)
CuevoPointsEntry *--1 MatchFrame (nullable, Team per-frame points)
```

Key design decision: **`fixtures.participant_a`/`participant_b` and `match_results.winner` reference `stage_participations.id`, not `players.id`/`teams.id` directly.** `StageParticipation` is already the union type (exactly-one-of player/team, tagged with category/stage/region) built in 5a specifically to solve this. Referencing it a second time on `Fixture`/`MatchResult` avoids re-introducing the Rails-polymorphic problem (Iron Law #3) at the fixture/result layer — one FK type, one join, and `Fixture`'s FR-006 same-category/same-stage check becomes a trivial comparison of two `StageParticipation` rows instead of a branchy player-or-team lookup.

---

## Migration 1 — `create_stages` (T064)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateStages do
  use Ecto.Migration

  def change do
    create table(:stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :order, :integer, null: false

      timestamps()
    end

    create unique_index(:stages, [:name])
    create unique_index(:stages, [:order])

    # Seed the four fixed pipeline stages (FR-001). Seeding inside the
    # migration (not priv/repo/seeds.exs) guarantees every environment,
    # including test, has these rows — every other Competitions table FKs
    # into `stages`.
    execute(
      """
      INSERT INTO stages (id, name, "order", inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'Grassroots', 1, now(), now()),
        (gen_random_uuid(), 'Regional', 2, now(), now()),
        (gen_random_uuid(), 'Circuit', 3, now(), now()),
        (gen_random_uuid(), 'Finals', 4, now(), now())
      """,
      "DELETE FROM stages WHERE name IN ('Grassroots', 'Regional', 'Circuit', 'Finals')"
    )
  end
end
```

Note: `order` is a reserved word in Postgres — must be double-quoted in raw SQL as shown; as an `add :order, :integer` column via the DSL, Ecto/Postgrex already quotes identifiers so no escaping is needed there. Confirm `pgcrypto`/`gen_random_uuid()` is available (Postgres 13+ has it built in; if not, use `Ecto.UUID.generate()` seeded from an `Ecto.Migration.execute/1` with placeholders via `Repo.insert_all` in a `priv/repo/seeds.exs` script instead — flag this as an environment check, not a schema question).

### Schema

```elixir
defmodule Cuevolution.Competitions.Stage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stages" do
    field :name, :string
    field :order, :integer

    timestamps()
  end

  # Stages are seeded, effectively read-only in application code; changeset
  # exists mainly for completeness/admin tooling, not general writes.
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name, :order])
    |> validate_required([:name, :order])
    |> unique_constraint(:name)
    |> unique_constraint(:order)
  end
end
```

---

## Migration 2 — `create_stage_capacity_configs` (T065)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateStageCapacityConfigs do
  use Ecto.Migration

  def change do
    create table(:stage_capacity_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :capacity_limit, :integer, null: false
      add :current_count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:stage_capacity_configs, [:stage_id, :category])

    create constraint(:stage_capacity_configs, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    create constraint(:stage_capacity_configs, :capacity_limit_must_be_positive,
             check: "capacity_limit > 0"
           )

    create constraint(:stage_capacity_configs, :current_count_must_be_non_negative,
             check: "current_count >= 0"
           )

    # Seed default Circuit/Finals capacities (FR-005/FR-006). Grassroots and
    # Regional are open/uncapped (FR-002) and intentionally get no config
    # rows — `capacity_config/2` returning nil for those stages IS the
    # "open" signal `advance_to_stage/2` checks against.
    execute(
      """
      INSERT INTO stage_capacity_configs (id, stage_id, category, capacity_limit, current_count, inserted_at, updated_at)
      SELECT gen_random_uuid(), s.id, v.category, v.capacity_limit, 0, now(), now()
      FROM stages s
      JOIN (VALUES
        ('Circuit', 'male', 128),
        ('Circuit', 'female', 64),
        ('Circuit', 'team', 20),
        ('Finals', 'male', 64),
        ('Finals', 'female', 32),
        ('Finals', 'team', 8)
      ) AS v(stage_name, category, capacity_limit) ON v.stage_name = s.name
      """,
      "DELETE FROM stage_capacity_configs"
    )
  end
end
```

### Schema

```elixir
defmodule Cuevolution.Competitions.StageCapacityConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stage_capacity_configs" do
    field :category, :string
    field :capacity_limit, :integer
    field :current_count, :integer, default: 0

    belongs_to :stage, Cuevolution.Competitions.Stage

    timestamps()
  end

  @categories ~w(male female team)

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:stage_id, :category, :capacity_limit])
    |> validate_required([:stage_id, :category, :capacity_limit])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:capacity_limit, greater_than: 0)
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:stage_id, :category])
  end
end
```

---

## Migration 3 — `create_stage_participations` (T066)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateStageParticipations do
  use Ecto.Migration

  def change do
    create table(:stage_participations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all)
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all)
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :joined_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:stage_participations, [:stage_id, :region_id, :category])
    create index(:stage_participations, [:player_id])
    create index(:stage_participations, [:team_id])

    create constraint(:stage_participations, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    # Exactly one of player_id/team_id must be set (Key Entities: "Stage
    # Participation" — a record of a PLAYER'S OR TEAM'S current stage).
    # Expressed via Ecto's `constraint/3` DSL (compiles to a real Postgres
    # CHECK constraint) — no raw `execute/1` needed, same mechanism already
    # used for players.gender.
    create constraint(:stage_participations, :exactly_one_participant_type,
             check: """
             (player_id IS NOT NULL AND team_id IS NULL) OR
             (player_id IS NULL AND team_id IS NOT NULL)
             """
           )
  end
end
```

### Schema

```elixir
defmodule Cuevolution.Competitions.StageParticipation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stage_participations" do
    field :category, :string
    field :joined_at, :utc_datetime

    belongs_to :player, Cuevolution.Accounts.Player
    belongs_to :team, Cuevolution.Teams.Team
    belongs_to :region, Cuevolution.Accounts.Region
    belongs_to :stage, Cuevolution.Competitions.Stage

    timestamps()
  end

  @categories ~w(male female team)

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [:player_id, :team_id, :region_id, :stage_id, :category, :joined_at])
    |> validate_required([:region_id, :stage_id, :category, :joined_at])
    |> validate_inclusion(:category, @categories)
    |> validate_exactly_one_participant()
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:region_id)
    |> foreign_key_constraint(:stage_id)
    |> check_constraint(:player_id, name: :exactly_one_participant_type)
  end

  defp validate_exactly_one_participant(changeset) do
    player_id = get_field(changeset, :player_id)
    team_id = get_field(changeset, :team_id)

    case {player_id, team_id} do
      {nil, nil} -> add_error(changeset, :player_id, "either player or team must be set")
      {p, t} when not is_nil(p) and not is_nil(t) -> add_error(changeset, :player_id, "cannot set both player and team")
      _ -> changeset
    end
  end
end
```

Note: `team_id` on_delete is `:delete_all` here, deliberately different from `teams.captain_id`/general FK conventions elsewhere — a stage participation record has no meaning once the player/team it tracks is gone. This mirrors `admin_tokens`/`player_tokens` → `:delete_all`, not the `:restrict` used for lookup-table parents like `regions`/`stages`.

---

## Migration 4 — `create_groups`, `create_group_memberships`, `create_knockout_brackets` (T072)

One migration file per tasks.md's grouping, or all three in one file since they're introduced together in T072 — recommend **one file** (`..._create_groups_and_brackets.exs`) matching the task's own bundling, since `knockout_brackets` FKs into `groups` created in the same migration and Ecto migrations execute sequentially within one file without issue.

```elixir
defmodule Cuevolution.Repo.Migrations.CreateGroupsAndBrackets do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false

      timestamps()
    end

    create index(:groups, [:stage_id, :region_id])
    create unique_index(:groups, [:stage_id, :region_id, :name])

    create table(:group_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      add :stage_participation_id,
          references(:stage_participations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:group_memberships, [:group_id])
    create index(:group_memberships, [:stage_participation_id])
    # A participant can't be in the same group twice; can't easily be in two
    # DIFFERENT groups within the same stage either, but that's an
    # application-level invariant (checked via stage_participation_id being
    # unique per active stage, not enforced here) rather than a DB constraint
    # on this join table alone.
    create unique_index(:group_memberships, [:group_id, :stage_participation_id])

    create table(:knockout_brackets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    # Regional-only, one bracket per group (FR-004).
    create unique_index(:knockout_brackets, [:group_id])
  end
end
```

### Schemas

```elixir
defmodule Cuevolution.Competitions.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :region, Cuevolution.Accounts.Region
    has_many :group_memberships, Cuevolution.Competitions.GroupMembership
    has_one :knockout_bracket, Cuevolution.Competitions.KnockoutBracket

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:stage_id, :region_id, :name])
    |> validate_required([:stage_id, :region_id, :name])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:region_id)
    |> unique_constraint([:stage_id, :region_id, :name])
  end
end

defmodule Cuevolution.Competitions.GroupMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "group_memberships" do
    belongs_to :group, Cuevolution.Competitions.Group
    belongs_to :stage_participation, Cuevolution.Competitions.StageParticipation

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:group_id, :stage_participation_id])
    |> validate_required([:group_id, :stage_participation_id])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:stage_participation_id)
    |> unique_constraint([:group_id, :stage_participation_id])
  end
end

defmodule Cuevolution.Competitions.KnockoutBracket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "knockout_brackets" do
    belongs_to :group, Cuevolution.Competitions.Group

    timestamps()
  end

  def changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:group_id])
    |> validate_required([:group_id])
    |> foreign_key_constraint(:group_id)
    |> unique_constraint(:group_id)
  end
end
```

---

## Migration 5 — `create_rounds`, `create_fixtures` (T077)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateRoundsAndFixtures do
  use Ecto.Migration

  def change do
    create table(:rounds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      # Nullable: knockout-stage rounds may be tied to a knockout_bracket
      # rather than a group directly in a later phase; group-stage rounds
      # (Grassroots/Regional) always set this.
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false

      timestamps()
    end

    create index(:rounds, [:stage_id])
    create index(:rounds, [:group_id])

    create table(:fixtures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :round_id, references(:rounds, type: :binary_id, on_delete: :delete_all), null: false

      add :participant_a_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :participant_b_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict), null: false
      add :scheduled_at, :utc_datetime, null: false

      # Forward reference: match_results doesn't exist until T086 (5d).
      # Plain binary_id column now; the real FK constraint is added via
      # `modify ... references(...), from: :binary_id` in the
      # create_match_results migration — same deferred-FK pattern used for
      # players.team_id -> teams.
      add :result_id, :binary_id

      timestamps()
    end

    create index(:fixtures, [:round_id])
    create index(:fixtures, [:participant_a_id])
    create index(:fixtures, [:participant_b_id])
    create index(:fixtures, [:venue_id])
    create unique_index(:fixtures, [:result_id])

    # FR-007: reject a duplicate pairing within the same round, regardless
    # of which participant is entered as "a" vs "b". least()/greatest() on
    # uuid work fine in Postgres (uuid has a default btree operator class).
    # Precedent: venues_region_lower_name_active_index (functional unique
    # index using a raw expression column).
    create unique_index(
             :fixtures,
             [:round_id, "least(participant_a_id, participant_b_id)", "greatest(participant_a_id, participant_b_id)"],
             name: :fixtures_round_participants_unique_index
           )

    create constraint(:fixtures, :participants_must_differ,
             check: "participant_a_id <> participant_b_id"
           )
  end
end
```

### Schemas

```elixir
defmodule Cuevolution.Competitions.Round do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rounds" do
    field :name, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :group, Cuevolution.Competitions.Group
    has_many :fixtures, Cuevolution.Competitions.Fixture

    timestamps()
  end

  def changeset(round, attrs) do
    round
    |> cast(attrs, [:stage_id, :group_id, :name])
    |> validate_required([:stage_id, :name])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:group_id)
  end
end

defmodule Cuevolution.Competitions.Fixture do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fixtures" do
    field :scheduled_at, :utc_datetime

    belongs_to :round, Cuevolution.Competitions.Round
    belongs_to :participant_a, Cuevolution.Competitions.StageParticipation
    belongs_to :participant_b, Cuevolution.Competitions.StageParticipation
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :result, Cuevolution.Competitions.MatchResult

    timestamps()
  end

  @doc "Create/edit changeset. Locked once `result_id` is set — see `Competitions.update_fixture/2`."
  def changeset(fixture, attrs, %{participant_a: pa, participant_b: pb}) do
    fixture
    |> cast(attrs, [:round_id, :participant_a_id, :participant_b_id, :venue_id, :scheduled_at])
    |> validate_required([:round_id, :participant_a_id, :participant_b_id, :venue_id, :scheduled_at])
    |> validate_same_category_and_stage(pa, pb)
    |> foreign_key_constraint(:round_id)
    |> foreign_key_constraint(:participant_a_id)
    |> foreign_key_constraint(:participant_b_id)
    |> foreign_key_constraint(:venue_id)
    |> check_constraint(:participant_a_id, name: :participants_must_differ)
    |> unique_constraint([:round_id, :participant_a_id, :participant_b_id],
      name: :fixtures_round_participants_unique_index,
      message: "this pairing already exists in this round"
    )
  end

  defp validate_same_category_and_stage(changeset, pa, pb) do
    cond do
      pa.category != pb.category ->
        add_error(changeset, :participant_b_id, "must be the same category as participant A")

      pa.stage_id != pb.stage_id ->
        add_error(changeset, :participant_b_id, "must be in the same stage as participant A")

      true ->
        changeset
    end
  end
end
```

Note on FR-006 cross-check: the changeset takes preloaded `StageParticipation` structs as a 3rd arg rather than re-querying inside the changeset (keeps the changeset pure/testable); `Competitions.enter_fixtures/2` is responsible for loading `pa`/`pb` before building each row's changeset.

---

## Migration 6 — `create_match_results` (T086) + deferred FK on `fixtures.result_id`

```elixir
defmodule Cuevolution.Repo.Migrations.CreateMatchResults do
  use Ecto.Migration

  def change do
    create table(:match_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fixture_id, references(:fixtures, type: :binary_id, on_delete: :delete_all), null: false

      add :winner_participation_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :score, :map
      add :prior_value, :map
      add :recorded_by_admin_id, references(:admins, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    # FR-007 dup guard: only one result per fixture, enforced at the DB
    # level, not just in the changeset.
    create unique_index(:match_results, [:fixture_id])
    create index(:match_results, [:winner_participation_id])
    create index(:match_results, [:recorded_by_admin_id])

    # Now that match_results exists, wire up the forward reference left
    # plain in the fixtures migration (same pattern as
    # add_team_fk_to_players.exs).
    alter table(:fixtures) do
      modify :result_id, references(:match_results, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end
  end
end
```

### Schema

```elixir
defmodule Cuevolution.Competitions.MatchResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_results" do
    field :score, :map
    field :prior_value, :map

    belongs_to :fixture, Cuevolution.Competitions.Fixture
    belongs_to :winner_participation, Cuevolution.Competitions.StageParticipation
    belongs_to :recorded_by_admin, Cuevolution.Accounts.Admin
    has_many :match_frames, Cuevolution.Competitions.MatchFrame
    has_many :cuevo_points_entries, Cuevolution.Competitions.CuevoPointsEntry

    timestamps()
  end

  def create_changeset(result, attrs) do
    result
    |> cast(attrs, [:fixture_id, :winner_participation_id, :score, :recorded_by_admin_id])
    |> validate_required([:fixture_id, :winner_participation_id, :recorded_by_admin_id])
    |> foreign_key_constraint(:fixture_id)
    |> foreign_key_constraint(:winner_participation_id)
    |> foreign_key_constraint(:recorded_by_admin_id)
    |> unique_constraint(:fixture_id, message: "a result has already been recorded for this fixture")
  end

  @doc "Correction changeset — caller snapshots the pre-update struct into :prior_value before calling this."
  def correction_changeset(result, attrs) do
    result
    |> cast(attrs, [:winner_participation_id, :score, :prior_value])
    |> validate_required([:winner_participation_id])
  end
end
```

---

## Migration 7 — `create_match_frames` (T087)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateMatchFrames do
  use Ecto.Migration

  def change do
    create table(:match_frames, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_result_id, references(:match_results, type: :binary_id, on_delete: :delete_all),
        null: false

      add :home_player_id, references(:players, type: :binary_id, on_delete: :restrict), null: false
      add :away_player_id, references(:players, type: :binary_id, on_delete: :restrict), null: false
      add :winner_player_id, references(:players, type: :binary_id, on_delete: :restrict), null: false
      add :sequence, :integer, null: false

      timestamps()
    end

    create index(:match_frames, [:match_result_id])
    create unique_index(:match_frames, [:match_result_id, :sequence])
    create index(:match_frames, [:home_player_id])
    create index(:match_frames, [:away_player_id])

    create constraint(:match_frames, :winner_must_be_home_or_away,
             check: "winner_player_id = home_player_id OR winner_player_id = away_player_id"
           )

    create constraint(:match_frames, :sequence_must_be_positive, check: "sequence > 0")
  end
end
```

### Schema

```elixir
defmodule Cuevolution.Competitions.MatchFrame do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_frames" do
    field :sequence, :integer

    belongs_to :match_result, Cuevolution.Competitions.MatchResult
    belongs_to :home_player, Cuevolution.Accounts.Player
    belongs_to :away_player, Cuevolution.Accounts.Player
    belongs_to :winner_player, Cuevolution.Accounts.Player

    timestamps()
  end

  def changeset(frame, attrs) do
    frame
    |> cast(attrs, [:match_result_id, :home_player_id, :away_player_id, :winner_player_id, :sequence])
    |> validate_required([:match_result_id, :home_player_id, :away_player_id, :winner_player_id, :sequence])
    |> validate_number(:sequence, greater_than: 0)
    |> foreign_key_constraint(:match_result_id)
    |> foreign_key_constraint(:home_player_id)
    |> foreign_key_constraint(:away_player_id)
    |> foreign_key_constraint(:winner_player_id)
    |> check_constraint(:winner_player_id, name: :winner_must_be_home_or_away)
    |> unique_constraint([:match_result_id, :sequence])
  end
end
```

---

## Migration 8 — `create_cuevo_points_entries` (T088)

```elixir
defmodule Cuevolution.Repo.Migrations.CreateCuevoPointsEntries do
  use Ecto.Migration

  def change do
    create table(:cuevo_points_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :participant_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :match_result_id, references(:match_results, type: :binary_id, on_delete: :restrict),
        null: false

      add :match_frame_id, references(:match_frames, type: :binary_id, on_delete: :restrict)

      add :points, :integer, null: false
      add :prior_value, :map
      add :recorded_by_admin_id, references(:admins, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    # SUM-aggregation hot path (standings_for_category/1, points_total/1) —
    # index deliberately, not incidentally.
    create index(:cuevo_points_entries, [:participant_id])
    create index(:cuevo_points_entries, [:match_result_id])
    create index(:cuevo_points_entries, [:match_frame_id])
  end
end
```

### Schema

```elixir
defmodule Cuevolution.Competitions.CuevoPointsEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cuevo_points_entries" do
    field :points, :integer
    field :prior_value, :map

    belongs_to :participant, Cuevolution.Competitions.StageParticipation
    belongs_to :match_result, Cuevolution.Competitions.MatchResult
    belongs_to :match_frame, Cuevolution.Competitions.MatchFrame
    belongs_to :recorded_by_admin, Cuevolution.Accounts.Admin

    timestamps()
  end

  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:participant_id, :match_result_id, :match_frame_id, :points, :recorded_by_admin_id])
    |> validate_required([:participant_id, :match_result_id, :points, :recorded_by_admin_id])
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:match_result_id)
    |> foreign_key_constraint(:match_frame_id)
    |> foreign_key_constraint(:recorded_by_admin_id)
  end

  def correction_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:points, :prior_value])
    |> validate_required([:points])
  end
end
```

---

## T069's atomic capacity update as `Ecto.Multi`

```elixir
defmodule Cuevolution.Competitions do
  alias Cuevolution.Repo
  alias Cuevolution.Competitions.{StageCapacityConfig, StageParticipation}
  import Ecto.Query

  def advance_to_stage(%StageParticipation{} = participation, %{id: stage_id} = _target_stage) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:capacity_check, fn repo, _changes ->
      case repo.one(
             from c in StageCapacityConfig,
               where: c.stage_id == ^stage_id and c.category == ^participation.category
           ) do
        # No config row = open/uncapped stage (Grassroots/Regional) — never rejects.
        nil ->
          {:ok, :uncapped}

        %StageCapacityConfig{id: config_id} ->
          # The atomic conditional UPDATE: capacity check + increment in one
          # statement, closing the TOCTOU race between two concurrent
          # advancements at the last remaining slot.
          {count, _} =
            repo.update_all(
              from(c in StageCapacityConfig,
                where: c.id == ^config_id and c.current_count < c.capacity_limit
              ),
              inc: [current_count: 1]
            )

          if count == 1, do: {:ok, :incremented}, else: {:error, :capacity_exceeded}
      end
    end)
    |> Ecto.Multi.update(:participation, fn _changes ->
      StageParticipation.changeset(participation, %{stage_id: stage_id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{participation: participation}} -> {:ok, participation}
      {:error, :capacity_check, :capacity_exceeded, _changes} -> {:error, :capacity_exceeded}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end
end
```

`repo.update_all` (not raw `execute/2`) is sufficient here — Ecto's query DSL already expresses `current_count = current_count + 1 WHERE current_count < capacity_limit` via `inc:` + a `where` comparing two columns; no raw SQL string needed. This is the direct analogue of the "atomic conditional update" pattern the plan.md cites as already used for spec 005's one-team-per-player guard.

---

## Where raw SQL genuinely is/isn't required

| Constraint | Ecto DSL sufficient? | Notes |
|---|---|---|
| T066 exactly-one-of-player/team CHECK | Yes — `constraint(table, name, check: "...")` | Same macro as `players.gender`; just a longer boolean expression |
| T065 composite unique `(stage_id, category)` | Yes — `unique_index/3` | Plain column list |
| T077 order-independent duplicate pairing | Yes — `unique_index/3` with `"least(...)"`/`"greatest(...)"` string index entries | Same functional-index mechanism as `players_lower_username_index`/`venues_region_lower_name_active_index`; not raw SQL, just non-plain-column index expressions |
| T086 unique `fixture_id` | Yes — `unique_index/2` | Plain column |
| T069 atomic capacity increment | Yes — `Repo.update_all/2` with `inc:` + column-comparison `where` | Handled in application code (`Ecto.Multi`), not a migration; no `Ecto.Adapters.SQL.query/3` needed |
| Seed data for `stages`/`stage_capacity_configs` | `execute/2` (raw SQL) used for convenience/idempotent down-migration | Could alternatively use `Repo.insert_all/3` in a `priv/repo/seeds.exs`, but doing it in the migration guarantees test/dev/CI parity without a separate seed step |

Bottom line: **none of the CHECK/unique constraints actually require raw SQL** — Ecto's migration DSL (`constraint/3`, `unique_index/3` with expression strings) covers all of them, consistent with existing precedent in this codebase. The only `execute/2` usage recommended here is for seeding `stages` and `stage_capacity_configs` rows, which is a data-loading concern, not a constraint-expression limitation.

---

## Migration file / ordering summary

1. `..._create_stages.exs` (T064) — seeds 4 stages
2. `..._create_stage_capacity_configs.exs` (T065) — seeds Circuit/Finals rows
3. `..._create_stage_participations.exs` (T066)
4. `..._create_groups_and_brackets.exs` (T072) — groups + group_memberships + knockout_brackets
5. `..._create_rounds_and_fixtures.exs` (T077) — fixtures.result_id left as plain binary_id
6. `..._create_match_results.exs` (T086) — also does `modify fixtures.result_id, references(...)`
7. `..._create_match_frames.exs` (T087)
8. `..._create_cuevo_points_entries.exs` (T088)

A 9th follow-up migration (outside T064–T103's numbering but flagged by tasks.md's "⚠️ blocked" list) wires `teams.roster_locked_at` to actually get set once `MatchResult` exists — that's an application-logic change (T058/T061), not a schema change, so no additional migration is needed for it.

## Performance notes carried into T102

- `group_standings/1` / `regional_top_8/1`: hot query joins `match_results` → `fixtures` → `stage_participations` filtered by `group_id`/`stage_id`; the `[:stage_id, :region_id, :category]` index on `stage_participations` and `[:round_id]`/`[:participant_a_id]`/`[:participant_b_id]` indexes on `fixtures` back this. Run `EXPLAIN ANALYZE` once seeded with hundreds of Grassroots participants per T102 — if group-by-group standings scan `match_results` sequentially, consider adding `index(:match_results, [:fixture_id])` explicitly (currently only covered by the unique index, which already backs equality lookups, so likely redundant — confirm via `EXPLAIN` before adding).
- `standings_for_category/1`: `SUM(points) GROUP BY participant_id` — the `cuevo_points_entries.participant_id` index is exactly what this needs; `ORDER BY points DESC` happens post-aggregation in-memory or via a `HAVING`/outer `ORDER BY`, no extra index required at MVP scale.
