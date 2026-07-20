# Codebase Patterns for `Cuevolution.Competitions`

No Ash Framework detected (`mix.exs` has no ash deps, no `use Ash.Domain` anywhere). Standard
Phoenix Context patterns apply.

## 1. Context module structure

Every context (`Accounts`, `Teams`, `Venues`, `Notifications`) follows the same shape:

```elixir
defmodule Cuevolution.Teams do
  @moduledoc """
  The Teams context: team registration and roster management (spec 005).
  """
  import Ecto.Query
  require Logger

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias Ecto.Multi

  @doc """..."""
  def create_team(%Player{} = captain, attrs), do: ...
end
```

Notes:

- **No `%Scope{}` struct anywhere in this codebase** — `grep -r "defmodule.*Scope" lib/` is empty.
  Despite Phoenix 1.8.5 being in use, this app does NOT follow the 1.8 built-in-scope convention.
  Context functions instead take the relevant domain struct directly as first arg (e.g.
  `create_team(%Player{} = captain, attrs)`, `add_player_to_roster(%Team{} = team, %Player{} =
  player)`, `deactivate_venue(%Venue{} = venue)`). **`Competitions` should follow this existing
  convention, not introduce a `Scope` struct** — introducing scopes now would be inconsistent with
  every other context in the app. If admin-only authorization is needed it's handled at the
  LiveView/router level (`current_admin` in socket assigns), not passed into context functions.
- `@moduledoc` always references the spec number that motivated the context/function (e.g. "spec
  005 FR-001", "spec 003 US1"). `Competitions` functions should cite spec 006/007/008/009 +
  requirement IDs the same way.
- Every public function has a `@doc` that explains not just what it does but *why* (race
  conditions closed, deferred work, caveats). Deferred/future work is called out with a "⚠️" prefix
  when relevant to future specs — e.g. `Teams.create_team/2`'s doc: "⚠️ The roster-freeze clause
  (FR-008, once `team.roster_locked_at` is set) is deferred until `Competitions.MatchResult`
  exists — not implemented yet." **This means `Competitions` needs to go implement/consume that
  deferred roster freeze.**
- Error tuple conventions:
  - Changeset validation failures: `{:error, %Ecto.Changeset{}}`
  - Business-rule failures: `{:error, :atom_reason}` (e.g. `:already_on_a_team`, `:roster_full`,
    `:not_on_this_team`, `:invalid_credentials`)
  - Success: `{:ok, struct}`
- Private helpers (query filters, claim queries, dispatch-with-rescue wrappers) live at the bottom
  of the same context module as `defp`, right after the public function that uses them (not in a
  separate helpers module).
- Filterable "admin directory" list functions follow one shared shape:
  `list_x_filtered(filters \\ %{})` piping `where`/`filter_by_*` clauses, `order_by`, `preload`,
  `Repo.all()`, with each filter clause split into its own `defp filter_by_x(query, nil), do:
  query` / `defp filter_by_x(query, val), do: where(...)` pair. `Competitions` should reuse this
  shape for e.g. `list_fixtures_filtered/1`, `list_standings/1`.
- Substring search filters normalize with a shared escape helper pattern:
  `pattern = "%" <> String.replace(value, ~w(% _), fn c -> "\\" <> c end) <> "%"` then
  `where(query, [t], ilike(t.field, ^pattern))`.

## 2. Concurrency-safe write pattern (Ecto.Multi + atomic claim)

Full pattern from `lib/cuevolution/teams.ex` (read in full) — this is the template `advance_to_stage/2`
(spec 006), fixture-entry duplicate guards (spec 007), and match-result duplicate guards (spec 008)
must mirror:

```elixir
def create_team(%Player{} = captain, attrs) do
  changeset = Team.changeset(%Team{}, %{...})

  Multi.new()
  |> Multi.insert(:team, changeset)
  |> Multi.update_all(
    :claim_captain,
    fn %{team: team} -> claim_query(captain.id, team.id) end,
    []
  )
  |> Multi.run(:verify_claim, fn _repo, %{claim_captain: {count, _}} ->
    if count == 1, do: {:ok, count}, else: {:error, :already_on_a_team}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{team: team}} -> {:ok, team}
    {:error, :team, changeset, _changes} -> {:error, changeset}
    {:error, :verify_claim, :already_on_a_team, _changes} -> {:error, :already_on_a_team}
  end
end

defp claim_query(player_id, team_id) do
  from(p in Player,
    where: p.id == ^player_id and is_nil(p.team_id),
    update: [set: [team_id: ^team_id]]
  )
end
```

Key mechanics of the pattern:

1. Insert/build the "owning" row first inside the Multi.
2. Race-close with `Multi.update_all/4` doing a conditional `update_all` — the `where` clause
   includes the "not already claimed" condition (`is_nil(p.team_id)`) so it's atomic at the DB
   level: only one concurrent transaction's `update_all` can match/affect the row.
3. `Multi.run(:verify_claim, ...)` inspects the `{count, _}` returned by `update_all` — `count ==
   1` means this transaction won the race, `count == 0` means it lost, so `{:error,
   :already_thing}` is returned and the whole transaction (including the just-inserted row) rolls
   back.
4. The final `Repo.transaction()` result is pattern-matched by Multi step name to translate into
   the context's public `{:ok, _}` / `{:error, _}` contract.
5. There's a real concurrency test proving this (`test/cuevolution/teams_concurrency_test.exs`,
   read in full) — spawns 5 concurrent `Task.async_stream` calls at `max_concurrency: 5` against
   the same contested row, asserts exactly 1 success + N-1 `{:error, :already_on_a_team}`, using
   `async: false` (shared sandbox mode) since real OS processes hit the same DB connection.
   `Competitions` concurrency-critical functions (e.g. simultaneous fixture entry, simultaneous
   match-result submission) need equivalent `*_concurrency_test.exs` files.

For non-racy multi-step removals, a plain conditional `update_all` without a wrapping `Multi` is
used instead (`Teams.remove_player_from_roster/2`):

```elixir
Player
|> where(id: ^player.id, team_id: ^team.id)
|> Repo.update_all(set: [team_id: nil])
|> case do
  {1, _} -> {:ok, Repo.get!(Player, player.id)}
  {0, _} -> {:error, :not_on_this_team}
end
```

## 3. Migration conventions

From `priv/repo/migrations/20260710134742_create_teams.exs`,
`20260711170344_create_notifications.exs`, `20260711145658_add_unique_index_to_players_mobile_number.exs`
(all read in full):

- Every table: `create table(:x, primary_key: false) do add :id, :binary_id, primary_key: true`.
  `Ecto.UUID`/`binary_id` throughout, no integer PKs.
- Foreign keys: `add :region_id, references(:regions, type: :binary_id, on_delete: :restrict),
  null: false` — `:restrict` is the default `on_delete` seen for "hard" ownership FKs
  (team→region, team→captain). `:delete_all` is used where the child is pure dependent data
  (`notifications.player_id references(:players, ..., on_delete: :delete_all)`). Competitions
  tables should default to `:restrict` for reference FKs to Accounts/Teams/Venues, and consider
  `:delete_all` only for genuinely dependent rows (e.g. `MatchFrame` under `MatchResult`).
- `timestamps()` macro (no explicit type override seen → Ecto default, `naive_datetime`) is used
  on every table; `roster_locked_at` uses explicit `:utc_datetime` for a semantically-meaningful
  timestamp column (not a `timestamps()`-generated one).
- Plain `create index(:table, [:col])` for FK/filter columns (e.g. `region_id`, `captain_id`,
  `player_id`, `status`).
- `create unique_index(:table, [:col])` for true uniqueness (`notifications.idempotency_key`,
  `players.mobile_number`) — added as its own follow-up migration when retrofitted
  (`20260711145658_add_unique_index_to_players_mobile_number.exs` is a single-purpose migration
  just for that index). No composite/partial unique indexes seen yet in this codebase, but the
  `Teams.create_team/2` atomic-claim pattern (section 2) is the mechanism used instead of a DB
  unique constraint for "one active team membership" — Competitions duplicate-guards (e.g. one
  `StageParticipation` per player per stage, one `Fixture` slot per participant) should evaluate
  whether a real partial-unique index (`where: is_nil(...)`) plus atomic claim, or a straightforward
  unique index, fits better case by case.
- Check constraints for enum-like string columns: `create constraint(:notifications,
  :channel_must_be_valid, check: "channel IN ('email', 'sms')")`. Competitions status/type enums
  (fixture status, match result status, etc.) stored as strings should get the same DB-level check
  constraint pattern, matching whatever `Ecto.Changeset` validation exists on the schema.
- Separate migrations per FK when added after the fact (e.g.
  `20260710134743_add_team_fk_to_players.exs` for the `team_id` back-reference on `players`,
  added right after `create_teams`), rather than editing the original create migration.

## 4. Notifications integration

`lib/cuevolution/notifications.ex` (read in full):

```elixir
@allowed_payload_keys %{
  "registration_confirmation" => [],
  "fixture_assignment" => ~w(opponent_name venue date time),
  "team_assignment" => ~w(team_name captain_name)
}

def dispatch(%Player{} = recipient, event_type, payload \\ %{}) when is_atom(event_type) do
  event_type = Atom.to_string(event_type)
  safe_payload = validate_payload!(event_type, payload)

  recipient
  |> channels_for()
  |> Enum.map(&enqueue(recipient, event_type, &1, safe_payload))
end
```

- `@allowed_payload_keys` **already has `"fixture_assignment" => ~w(opponent_name venue date
  time)`** predefined — spec 007's fixture-entry dispatch is expected to call
  `Notifications.dispatch(player, :fixture_assignment, %{opponent_name: ..., venue: ..., date:
  ..., time: ...})` with exactly those keys; passing any other key raises `ArgumentError`
  (`validate_payload!/2` diffs `Map.keys(payload) -- allowed`).
- `dispatch/3` fans out to one `Notification` DB row + one Oban job (`SendEmailWorker` /
  `SendSmsWorker`) per channel implied by the recipient's `notification_preference`
  (`"email"`/`"sms"`/`"both"`).
- Caller-side integration pattern (seen identically in both `Accounts.register_player/1` and
  `Teams.add_player_to_roster/2`): call `dispatch/3` **after** the write already committed, wrapped
  in a private helper that rescues and logs, never re-raises or rolls back:

```elixir
defp dispatch_team_assignment(player, team) do
  team = Repo.preload(team, :captain)
  captain_name = "#{team.captain.first_name} #{team.captain.last_name}"

  Notifications.dispatch(player, :team_assignment, %{
    team_name: team.name,
    captain_name: captain_name
  })
rescue
  error ->
    Logger.error(
      "team_assignment dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
    )
    :ok
end
```

Spec 007's fixture-assignment dispatch should be a `defp dispatch_fixture_assignment(player,
fixture)` (or similar) in the Competitions context following this exact rescue/log/`:ok` shape,
called post-commit from whichever function creates/confirms a fixture entry.

## 5. Test/factory conventions

`test/support/factory.ex` (ExMachina, read in full):

```elixir
defmodule Cuevolution.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Cuevolution.Repo
  import Ecto.Query
  alias Cuevolution.Accounts.{Admin, Player, Region}
  alias Cuevolution.Teams.Team
  alias Cuevolution.Venues.Venue

  def player_factory do
    region = build(:region)
    %Player{ ...sequence(:field, &"...#{&1}")... , region_id: region.id}
  end

  def team_factory do
    captain = insert(:player)
    %Team{name: sequence(:team_name, &"Team #{&1}"), region_id: captain.region_id, captain_id: captain.id}
  end
end
```

- `region_factory` cycles deterministically through real seeded regions (`sequence(:region_cycle,
  & &1) |> rem(length(regions))`) rather than building fake ones — Competitions factories that
  need a region should `build(:region)` the same way.
- Factories that need a persisted association call `insert(:assoc)` directly inside the factory
  function body (see `team_factory`'s `captain = insert(:player)`), not `build`, when the FK must
  reference a real row. Doc comments call out any intentionally-incomplete bidirectional
  consistency the caller should be aware of (team_factory's comment: captain's own `team_id` isn't
  back-filled, because that's `Teams.create_team/2`'s job to guarantee — tests needing full
  consistency should go through the context function, not the factory shortcut). Competitions
  factories for `Fixture`/`MatchResult`/etc. should add equivalent comments if they take similar
  shortcuts.
- `test/support/data_case.ex`: `use Cuevolution.DataCase, async: true` (or omit `async` for
  `false`) sets up `Ecto.Adapters.SQL.Sandbox` per test — `shared: not tags[:async]`. Also wires up
  `use Oban.Testing, repo: Cuevolution.Repo` and auto-imports `Ecto`, `Ecto.Changeset`,
  `Ecto.Query`, `Cuevolution.DataCase`, `Cuevolution.Factory` into every test module.
- Concurrency tests must use `async: false` (shared sandbox) since they spawn real processes —
  see `test/cuevolution/teams_concurrency_test.exs` (read in full):

```elixir
defmodule Cuevolution.TeamsConcurrencyTest do
  use Cuevolution.DataCase, async: false
  alias Cuevolution.Teams

  test "concurrent create_team calls for the same player: exactly one succeeds" do
    captain = insert(:player)
    results =
      1..5
      |> Task.async_stream(fn i -> Teams.create_team(captain, %{"name" => "Team #{i}"}) end,
        max_concurrency: 5, timeout: 5_000)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_on_a_team})) == 4
  end
end
```

- Existing context test files to mirror structurally: `test/cuevolution/teams_test.exs`,
  `test/cuevolution/accounts_test.exs`, `test/cuevolution/venues_test.exs`,
  `test/cuevolution/notifications_test.exs` — one `*_test.exs` per context, plus a separate
  `*_concurrency_test.exs` file specifically for race-condition tests (kept out of the main test
  file, presumably so the main suite can stay `async: true`).

## 6. Admin LiveView chrome

`lib/cuevolution_web/components/admin_components.ex` (read in full) already provides:

- `AdminComponents.app_shell/1` — dark sidebar + light content area. Required attrs:
  `current_admin`, `active` (one of `:dashboard, :draws, :results, :directory, :venues` — **this
  atom list is hardcoded in `nav_active?/2` clauses and the `@nav_items` module attribute; adding
  new Competitions pages (stages, groups, fixtures, standings) means editing `@nav_items` and
  `nav_active?/2` in this file**, or reusing one of the existing five tabs, e.g. folding
  stages/groups/fixtures under "Draws" and match results/standings under "Results & Points" per
  the existing nav labels), `flash`. Wraps `inner_block` in `<main>`.
- `AdminComponents.card/1` — the generic white rounded-2xl bordered panel wrapper, `class` attr
  passthrough.
- `AdminComponents.stat_tile/1` — dashboard stat display (`label`, `value`, optional `delta`/`delta_class`).
- `AdminComponents.eyebrow/1` — small uppercase red mono label above page titles.
- `AdminComponents.field_search/1` — live-search combobox already built for the Draws page's
  fixture-entry participant/venue picker (`row_id`, `field`, `value`, `placeholder`, `confirmed`,
  `suggestions`), driven by a single `phx-keyup="field_keyup"` binding (doc comment explicitly
  warns against adding a second `phx-keydown` binding on the same input — LiveView's per-element
  key-match/debounce state starves one of the two bindings). **Spec 007's fixture-entry UI should
  reuse `field_search/1` directly rather than re-building a combobox.**
- Admin flash: `phx-hook=".AdminAutoDismissFlash"` colocated hook, auto-dismiss after 5000ms via
  `setTimeout(() => this.el.click(), 5000)`.

`lib/cuevolution_web/live/admin/venue_management_live.ex` + `.html.heex` (both read in full) is
the best full CRUD reference:

- Region-tab select pattern: `assign(:regions, ...)`, default `region = List.first(regions)`,
  `handle_event("select_region", %{"id" => region_id}, socket)` re-derives `region` from
  `Enum.find(socket.assigns.regions, &(&1.id == region_id))` and reloads dependent assigns.
  Competitions' Stage/Group/Fixture LiveViews scoped per-region or per-stage should mirror this
  tab-select-then-reload shape.
- Inline edit form pattern: single `@form` assign shared between the "create" form (shown when
  `@editing_venue` is nil) and the "edit" form (shown inline in the row when
  `@editing_venue.id == row.id`), both submitting to the same `"validate"`/`"save"` events; `save`
  branches on `if venue = socket.assigns.editing_venue, do: Venues.update_venue(...), else:
  Venues.create_venue(...)`.
- `assign_form/2` private helper: `assign(socket, :form, to_form(changeset, as: :venue))`,
  consistently named/shaped across LiveViews.
- Activate/deactivate pattern: two mirrored `handle_event` clauses, `data-confirm` browser confirm
  dialog on the destructive one (`deactivate`), pill-badge styling for active/inactive state,
  `put_flash(:info, ...)` with a human-readable message quoting the entity name.
- All context calls (`Venues.list_venues/1`, `Venues.create_venue/1`,
  `Accounts.list_custom_venue_submissions/1`) go through the context module — no direct `Repo`
  query construction in the LiveView except simple `Repo.get!/2` lookups by id (`edit`,
  `deactivate`, `activate` handlers do `Repo.get!(Venue, id)` directly rather than adding a
  single-purpose context function for it — this is the one place Repo is touched directly in an
  admin LiveView, treated as acceptable for id-lookup-then-pass-to-context-function).

## 7. Phoenix.PubSub

`Phoenix.PubSub` is configured in the supervision tree (`lib/cuevolution/application.ex:14`:
`{Phoenix.PubSub, name: Cuevolution.PubSub}`) but **`grep -rn "PubSub.broadcast\|PubSub.subscribe"
lib/` returns nothing** — no context currently broadcasts or subscribes. Spec 009's standings
PubSub broadcast on points changes would be the **first actual usage** of PubSub in this app
beyond boot-time configuration; there's no existing in-house convention (topic naming, payload
shape, `handle_info` pattern) to match — this should be designed fresh, following general
Phoenix/LiveView community convention (e.g. `Phoenix.PubSub.broadcast(Cuevolution.PubSub, topic,
message)` called from the context after a successful `Repo.transaction`, `Phoenix.PubSub.subscribe/2`
in `mount/3` guarded by `if connected?(socket)`).
