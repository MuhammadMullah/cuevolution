defmodule Cuevolution.Competitions do
  @moduledoc """
  The Competitions context: the qualification pipeline (spec 006) — stages,
  per-stage/category capacity, stage participations, and grouping/knockout
  brackets — plus draws/fixtures (spec 007). Later specs (008 results/points,
  009 standings) extend this same module.
  """

  import Ecto.Query

  require Logger

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.CuevoPointsEntry
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Group
  alias Cuevolution.Competitions.GroupMembership
  alias Cuevolution.Competitions.KnockoutBracket
  alias Cuevolution.Competitions.MatchFrame
  alias Cuevolution.Competitions.MatchResult
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig
  alias Cuevolution.Competitions.StageGroupConfig
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Competitions.StandingsCalculator
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team
  alias Ecto.Multi

  # EAT = East Africa Time, UTC+3, fixed offset (no DST) — spec 007 FR-008.
  @eat_offset_seconds 3 * 60 * 60

  @doc "All 4 seeded stages, in pipeline order (Grassroots → Finals)."
  def list_stages do
    Repo.all(from s in Stage, order_by: s.order)
  end

  @doc "The stage immediately after `stage` in pipeline order, or `nil` if `stage` is Finals."
  def next_stage(%Stage{order: order}) do
    Repo.one(from s in Stage, where: s.order == ^(order + 1))
  end

  @doc "The first stage in pipeline order — every new player/team enters here (spec 006)."
  def grassroots_stage do
    Repo.one!(from s in Stage, where: s.order == 1)
  end

  @doc """
  Enrolls `player` into Grassroots under their gender category — the
  default entry point for every newly registered player (spec 006).
  Returns a changeset for composition inside a caller's `Ecto.Multi`.
  """
  def enroll_player_in_grassroots_changeset(%Player{} = player) do
    StageParticipation.changeset(%StageParticipation{}, %{
      player_id: player.id,
      region_id: player.region_id,
      stage_id: grassroots_stage().id,
      category: player.gender,
      joined_at: DateTime.utc_now()
    })
  end

  @doc """
  Enrolls `team` into Grassroots under the "team" category — the default
  entry point for every newly created team (spec 006). Returns a changeset
  for composition inside a caller's `Ecto.Multi`.
  """
  def enroll_team_in_grassroots_changeset(%Team{} = team) do
    StageParticipation.changeset(%StageParticipation{}, %{
      team_id: team.id,
      region_id: team.region_id,
      stage_id: grassroots_stage().id,
      category: "team",
      joined_at: DateTime.utc_now()
    })
  end

  @doc """
  Enrolls every player/team that predates auto-enrollment into Grassroots
  (spec 006 migration path). Idempotent — skips anyone who already has a
  participation for any stage. Shared by `Mix.Tasks.Cuevolution.BackfillGrassroots`
  (dev/test) and `Cuevolution.Release.backfill_grassroots/0` (production
  releases, which have no Mix), so the enrollment rule lives in one place.
  Returns `%{players: {count, errors}, teams: {count, errors}}`.
  """
  def backfill_grassroots_enrollments do
    %{players: backfill_player_enrollments(), teams: backfill_team_enrollments()}
  end

  defp backfill_player_enrollments do
    enrolled_ids = participation_owner_ids(:player_id)

    Player
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(enrolled_ids, &1.id))
    |> Enum.reduce({0, []}, fn player, {count, errors} ->
      case player |> enroll_player_in_grassroots_changeset() |> Repo.insert() do
        {:ok, _} -> {count + 1, errors}
        {:error, changeset} -> {count, [{player.id, changeset} | errors]}
      end
    end)
  end

  defp backfill_team_enrollments do
    enrolled_ids = participation_owner_ids(:team_id)

    Team
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(enrolled_ids, &1.id))
    |> Enum.reduce({0, []}, fn team, {count, errors} ->
      case team |> enroll_team_in_grassroots_changeset() |> Repo.insert() do
        {:ok, _} -> {count + 1, errors}
        {:error, changeset} -> {count, [{team.id, changeset} | errors]}
      end
    end)
  end

  defp participation_owner_ids(field) do
    StageParticipation
    |> where([sp], not is_nil(field(sp, ^field)))
    |> select([sp], field(sp, ^field))
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "The stage a participation currently sits in (spec 006)."
  def current_stage(%StageParticipation{} = participation) do
    participation |> Repo.preload(:stage) |> Map.fetch!(:stage)
  end

  @doc """
  Participations filtered by `:stage_id`, `:region_id`, `:category` (all
  optional) — the admin Stage/Group management screens' listing query.
  """
  def list_participations(filters \\ %{}) do
    StageParticipation
    |> filter_by(:stage_id, filters[:stage_id])
    |> filter_by(:region_id, filters[:region_id])
    |> filter_by(:category, filters[:category])
    |> preload([:player, :team, :region, :stage])
    |> Repo.all()
  end

  @doc """
  Maps each of the given player/team ids to their current `Stage`, in one
  indexed query. Used to annotate rows already loaded elsewhere (e.g. the
  admin Directory) with a stage badge — deliberately narrower than
  `list_participations/1`, which would otherwise have to load and preload
  *every* participation (player, team, region and stage included) in the
  whole competition just to look up a handful of ids.
  """
  def stages_by_participant(player_ids, team_ids) do
    StageParticipation
    |> where([sp], sp.player_id in ^player_ids or sp.team_id in ^team_ids)
    |> preload(:stage)
    |> Repo.all()
    |> Map.new(&{&1.player_id || &1.team_id, &1.stage})
  end

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, field, value), do: where(query, [p], field(p, ^field) == ^value)

  @doc "All capacity configs for `stage_id` (one per category, if any are seeded)."
  def list_capacity_configs(stage_id) do
    Repo.all(from c in StageCapacityConfig, where: c.stage_id == ^stage_id, order_by: c.category)
  end

  @doc """
  The capacity config for `stage_id`/`category`, or `nil` if none exists.
  `nil` is the intentional "open/uncapped" signal (Grassroots and Regional
  never have a seeded config row, spec 006 FR-002) — `advance_to_stage/2`
  checks against this, not an empty-vs-missing distinction.
  """
  def capacity_config(stage_id, category) do
    Repo.one(
      from c in StageCapacityConfig, where: c.stage_id == ^stage_id and c.category == ^category
    )
  end

  @doc "Admin-editable capacity update (NFR-2.2, no-deploy config change). Not concurrency-critical — single-writer admin action, plain changeset update."
  def update_capacity_config(%StageCapacityConfig{} = config, attrs) do
    config
    |> StageCapacityConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves `participation` to `target_stage` (spec 006 FR-002/FR-005/FR-006).

  Atomically checks and increments the destination stage's capacity via a
  conditional `UPDATE ... WHERE current_count < capacity_limit` — closes
  the race between two simultaneous advancements at the last remaining
  slot (only one can win). Stages with no capacity config (Grassroots,
  Regional) never reject. Lowering a capacity below the current count
  doesn't retroactively break existing participations — the conditional
  update only blocks *new* advancements going forward.
  """
  def advance_to_stage(%StageParticipation{} = participation, %Stage{id: stage_id}) do
    Multi.new()
    |> Multi.run(:capacity_check, fn repo, _changes ->
      check_and_claim_capacity(repo, stage_id, participation.category)
    end)
    |> Multi.update(:participation, fn _changes ->
      StageParticipation.changeset(participation, %{stage_id: stage_id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{participation: participation}} -> {:ok, participation}
      {:error, :capacity_check, :capacity_exceeded, _changes} -> {:error, :capacity_exceeded}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  defp check_and_claim_capacity(repo, stage_id, category) do
    config =
      repo.one(
        from c in StageCapacityConfig, where: c.stage_id == ^stage_id and c.category == ^category
      )

    claim_capacity(repo, config)
  end

  defp claim_capacity(_repo, nil), do: {:ok, :uncapped}

  defp claim_capacity(repo, %StageCapacityConfig{id: config_id}) do
    {count, _} =
      repo.update_all(
        from(c in StageCapacityConfig,
          where: c.id == ^config_id and c.current_count < c.capacity_limit
        ),
        inc: [current_count: 1]
      )

    if count == 1, do: {:ok, :incremented}, else: {:error, :capacity_exceeded}
  end

  @doc """
  Assigns `participation` to `group` (spec 006 FR-003/FR-004). Rejects a
  category mismatch between the participation and the group — groups are
  category-pure so `StageGroupConfig`'s per-category advancer-count cutoff
  means what it says.
  """
  def assign_to_group(%StageParticipation{category: category}, %Group{category: group_category})
      when category != group_category do
    {:error, :category_mismatch}
  end

  def assign_to_group(%StageParticipation{} = participation, %Group{} = group) do
    %GroupMembership{}
    |> GroupMembership.changeset(%{
      group_id: group.id,
      stage_participation_id: participation.id
    })
    |> Repo.insert()
  end

  @doc """
  Groups for `stage_id`/`category`, scoped to `{:region_id, id}` (Regional)
  or `{:venue_id, id}` (Grassroots), with membership count preloaded.
  """
  def list_groups(stage_id, category, scope) do
    Group
    |> where([g], g.stage_id == ^stage_id and g.category == ^category)
    |> filter_by_group_scope(scope)
    |> order_by(asc: :name)
    |> preload(group_memberships: [stage_participation: [:player, :team]])
    |> Repo.all()
  end

  defp filter_by_group_scope(query, {:region_id, region_id}),
    do: where(query, [g], g.region_id == ^region_id)

  defp filter_by_group_scope(query, {:venue_id, venue_id}),
    do: where(query, [g], g.venue_id == ^venue_id)

  @doc """
  Members of `group_id` matching `query` by player name/username or team
  name — backs the admin Draws page's participant suggestions for a
  Grassroots/Regional round, which spec 007 FR-011 restricts pairings to
  the round's group (`restrict_to_group/2` enforces the same scope at save
  time; this just narrows the live-search dropdown to match).
  """
  def search_group_members(group_id, query) do
    pattern = "%" <> escape_like_pattern(query) <> "%"

    from(gm in GroupMembership,
      join: p in StageParticipation,
      on: p.id == gm.stage_participation_id,
      left_join: player in assoc(p, :player),
      left_join: team in assoc(p, :team),
      where: gm.group_id == ^group_id,
      where:
        ilike(fragment("? || ' ' || ?", player.first_name, player.last_name), ^pattern) or
          ilike(player.username, ^pattern) or
          ilike(team.name, ^pattern),
      order_by: [asc: player.first_name, asc: team.name],
      limit: 6,
      select: p
    )
    |> Repo.all()
    |> Repo.preload([:player, team: [:region, :roster]])
  end

  defp escape_like_pattern(value), do: String.replace(value, ~w(% _), fn c -> "\\" <> c end)

  @doc """
  Participations in `stage_id`/`region_id`/`category` not yet in any group
  for that stage — the GroupManagementLive "unassigned" pool.
  """
  def list_unassigned_participations(stage_id, region_id, category) do
    grouped_ids =
      from(gm in GroupMembership,
        join: g in Group,
        on: g.id == gm.group_id,
        where: g.stage_id == ^stage_id and g.region_id == ^region_id and g.category == ^category,
        select: gm.stage_participation_id
      )

    StageParticipation
    |> where(
      [p],
      p.stage_id == ^stage_id and p.region_id == ^region_id and p.category == ^category
    )
    |> where([p], p.id not in subquery(grouped_ids))
    |> preload([:player, :team])
    |> Repo.all()
  end

  @doc """
  Creates a group for `stage_id`/`region_id`/`category` (spec 006). Never
  creates a knockout bracket — Grassroots and Regional are both round-robin
  only; brackets are Circuit/Finals stage+category constructs, unrelated to
  groups (`ensure_knockout_bracket/2`). `venue_id` is required when the
  target stage is Grassroots (venue-scoped pairing) and rejected otherwise
  (Regional is region-scoped).
  """
  def create_group(attrs) do
    stage = Repo.get!(Stage, attrs.stage_id)

    %Group{}
    |> Group.changeset(attrs)
    |> validate_group_venue(stage)
    |> Repo.insert()
  end

  defp validate_group_venue(changeset, %Stage{name: "Grassroots"}) do
    Ecto.Changeset.validate_required(changeset, [:venue_id],
      message: "is required for Grassroots-stage groups"
    )
  end

  defp validate_group_venue(changeset, _stage) do
    case Ecto.Changeset.get_field(changeset, :venue_id) do
      nil -> changeset
      _ -> Ecto.Changeset.add_error(changeset, :venue_id, "must be blank outside Grassroots")
    end
  end

  @doc "All group-size/advancer-count configs for `stage_id` (one per category, if any are seeded — Grassroots/Regional only)."
  def list_group_configs(stage_id) do
    Repo.all(from c in StageGroupConfig, where: c.stage_id == ^stage_id, order_by: c.category)
  end

  @doc "The group-size/advancer-count config for `stage_id`/`category` (spec 006 FR-011/FR-012), or `nil` if unseeded."
  def group_config(stage_id, category) do
    Repo.one(
      from c in StageGroupConfig, where: c.stage_id == ^stage_id and c.category == ^category
    )
  end

  @doc "Admin-editable group-size/advancer-count update (no-deploy config change, mirrors `update_capacity_config/2`)."
  def update_group_config(%StageGroupConfig{} = config, attrs) do
    config
    |> StageGroupConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc "The knockout bracket for `stage_id`/`category` (Circuit/Finals), or `nil` if not yet started."
  def get_knockout_bracket(stage_id, category) do
    Repo.one(
      from b in KnockoutBracket, where: b.stage_id == ^stage_id and b.category == ^category
    )
  end

  @doc "Get-or-insert the knockout bracket for `stage_id`/`category` (spec 006 User Story 5) — called when the admin starts the first knockout round for that stage+category."
  def ensure_knockout_bracket(stage_id, category) do
    case get_knockout_bracket(stage_id, category) do
      nil ->
        %KnockoutBracket{}
        |> KnockoutBracket.changeset(%{stage_id: stage_id, category: category})
        |> Repo.insert()
        |> case do
          {:ok, bracket} -> bracket
          {:error, _changeset} -> get_knockout_bracket(stage_id, category)
        end

      bracket ->
        bracket
    end
  end

  @doc """
  All groups for `stage_id`, any region/venue/category, with venue/region
  preloaded — the admin Draws page's round-creation group picker (Grassroots/
  Regional only; the admin picks an already-created group from
  GroupManagementLive directly, rather than free-form venue/region/category).
  """
  def list_groups_for_stage(stage_id) do
    Group
    |> where([g], g.stage_id == ^stage_id)
    |> order_by(asc: :name)
    |> preload([:venue, :region])
    |> Repo.all()
  end

  @doc "Rounds for `stage_id`, most recently created first — the admin Draws page's round picker."
  def list_rounds_for_stage(stage_id) do
    Repo.all(from r in Round, where: r.stage_id == ^stage_id, order_by: [desc: r.inserted_at])
  end

  @doc """
  All rounds across every stage, preloaded with `:stage` and ordered by
  stage pipeline order then most-recently-created — backs the admin Draws
  page's single combined "{Stage} — {Round}" picker (spec 007).
  """
  def list_rounds do
    Repo.all(
      from r in Round,
        join: s in assoc(r, :stage),
        order_by: [asc: s.order, desc: r.inserted_at],
        preload: [stage: s]
    )
  end

  @doc "Creates a round for `stage_id` (spec 007) — the admin Draws page's \"new round\" action."
  def create_round(attrs) do
    %Round{}
    |> Round.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fixtures already entered for `round_id`, most recently scheduled first —
  backs the admin Draws page's "Already entered" list. Preloads everything
  the row display needs (no N+1 per row).
  """
  def list_fixtures_for_round(round_id) do
    Fixture
    |> where([f], f.round_id == ^round_id)
    |> order_by(asc: :scheduled_at)
    |> preload([
      :venue,
      participant_a: [:player, :team],
      participant_b: [:player, :team]
    ])
    |> Repo.all()
  end

  @doc """
  Batch-enters `rows` of fixtures into `round` (spec 007 US1, FR-009).

  Each row gets its own transaction (not one big `Multi` across the whole
  batch) — a batch with one invalid row among N commits the valid rows and
  reports the specific error for the bad one, rather than rolling back
  everything. Returns a list of `{:ok, fixture} | {:error, reason}`, one
  per input row, in the same order.

  Row shape (matches `AdminDrawsLive`'s row assigns exactly):
  `%{"category" => cat, "a_kind" => "player"|"team", "a_id" => id,
    "b_kind" => ..., "b_id" => ..., "venue_id" => id, "date" => "YYYY-MM-DD",
    "time" => "HH:MM"}`.

  On success, dispatches a `fixture_assignment` notification to both
  participants post-commit (FR-002) — Team-category fixtures fan out to
  every roster member of both teams, since `Notifications.dispatch/3` only
  accepts a `%Player{}`.
  """
  def enter_fixtures(%Round{} = round, rows) when is_list(rows) do
    Enum.map(rows, &enter_fixture_row(round, &1))
  end

  defp enter_fixture_row(round, row) do
    Multi.new()
    |> Multi.run(:scheduled_at, fn _repo, _changes ->
      combine_eat_datetime(row["date"], row["time"])
    end)
    |> Multi.run(:participant_a, fn repo, _changes ->
      resolve_participant(repo, round, row["category"], row["a_kind"], row["a_id"])
    end)
    |> Multi.run(:participant_b, fn repo, _changes ->
      resolve_participant(repo, round, row["category"], row["b_kind"], row["b_id"])
    end)
    |> Multi.insert(:fixture, fn %{
                                   scheduled_at: scheduled_at,
                                   participant_a: pa,
                                   participant_b: pb
                                 } ->
      Fixture.changeset(
        %Fixture{},
        %{
          round_id: round.id,
          participant_a_id: pa.id,
          participant_b_id: pb.id,
          venue_id: row["venue_id"],
          scheduled_at: scheduled_at
        },
        %{participant_a: pa, participant_b: pb}
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{fixture: fixture, participant_a: pa, participant_b: pb}} ->
        dispatch_fixture_assignment(fixture, pa, pb)

        {:ok,
         Repo.preload(fixture, [
           :venue,
           participant_a: [:player, :team],
           participant_b: [:player, :team]
         ])}

      {:error, :scheduled_at, _reason, _changes} ->
        {:error, :invalid_datetime}

      {:error, :participant_a, reason, _changes} ->
        {:error, {:participant_a, reason}}

      {:error, :participant_b, reason, _changes} ->
        {:error, {:participant_b, reason}}

      {:error, :fixture, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp resolve_participant(_repo, _round, _category, _kind, nil),
    do: {:error, :participant_required}

  defp resolve_participant(repo, round, category, "player", player_id) do
    find_participant(repo, round, category, player_id: player_id)
  end

  defp resolve_participant(repo, round, category, "team", team_id) do
    find_participant(repo, round, category, team_id: team_id)
  end

  defp find_participant(repo, round, category, clauses) do
    query =
      from p in StageParticipation,
        where: p.stage_id == ^round.stage_id and p.category == ^category

    query =
      Enum.reduce(clauses, query, fn {field, value}, q ->
        where(q, [p], field(p, ^field) == ^value)
      end)

    query = restrict_to_group(query, round)

    case repo.one(query) do
      nil -> {:error, group_lookup_error(round)}
      participation -> {:ok, participation}
    end
  end

  # Group-stage rounds (Grassroots/Regional) restrict candidates to members
  # of that round's group — transitively enforcing same-venue (Grassroots)
  # or same-region (Regional) pairing, spec 007 FR-011. Knockout-stage rounds
  # (Circuit/Finals, `group_id` nil) are intentionally unrestricted — any
  # region may pair against any other.
  defp restrict_to_group(query, %Round{group_id: nil}), do: query

  defp restrict_to_group(query, %Round{group_id: group_id}) do
    member_ids =
      from gm in GroupMembership,
        where: gm.group_id == ^group_id,
        select: gm.stage_participation_id

    where(query, [p], p.id in subquery(member_ids))
  end

  defp group_lookup_error(%Round{group_id: nil}), do: :participant_not_in_stage
  defp group_lookup_error(%Round{}), do: :participant_not_in_group

  defp combine_eat_datetime(date_str, time_str) do
    with {:ok, date} <- Date.from_iso8601(to_string(date_str)),
         [h, m] <- String.split(to_string(time_str), ":"),
         {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(m),
         {:ok, time} <- Time.new(hour, minute, 0) do
      utc =
        date
        |> NaiveDateTime.new!(time)
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.add(-@eat_offset_seconds, :second)

      {:ok, utc}
    else
      _ -> {:error, :invalid_datetime}
    end
  end

  @doc "`fixture.scheduled_at` (stored UTC) converted to EAT for display — the one shared function used everywhere a fixture time renders (spec 007 FR-008)."
  def fixture_time_in_eat(%Fixture{scheduled_at: scheduled_at}) do
    DateTime.add(scheduled_at, @eat_offset_seconds, :second)
  end

  @doc """
  Updates `fixture`'s venue/schedule (spec 007 FR-003). Editable until a
  result exists; returns `{:error, :locked}` rather than silently no-op-ing
  once `fixture.result_id` is set (FR-004).
  """
  def update_fixture(%Fixture{result_id: nil} = fixture, attrs) do
    fixture
    |> Fixture.update_changeset(attrs)
    |> Repo.update()
  end

  def update_fixture(%Fixture{}, _attrs), do: {:error, :locked}

  defp dispatch_fixture_assignment(fixture, participant_a, participant_b) do
    fixture = Repo.preload(fixture, :venue)
    eat = fixture_time_in_eat(fixture)

    payload = %{
      venue: fixture.venue.name,
      date: Calendar.strftime(eat, "%Y-%m-%d"),
      time: Calendar.strftime(eat, "%H:%M")
    }

    a_name = participant_name(participant_a)
    b_name = participant_name(participant_b)

    Enum.each(participant_players(participant_a), &dispatch_one(&1, b_name, payload))
    Enum.each(participant_players(participant_b), &dispatch_one(&1, a_name, payload))
  end

  defp dispatch_one(player, opponent_name, payload) do
    Notifications.dispatch(
      player,
      :fixture_assignment,
      Map.put(payload, :opponent_name, opponent_name)
    )
  rescue
    error ->
      Logger.error(
        "fixture_assignment dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end

  defp participant_players(%StageParticipation{player_id: nil} = participation) do
    Repo.preload(participation, team: :roster).team.roster
  end

  defp participant_players(%StageParticipation{} = participation) do
    [Repo.preload(participation, :player).player]
  end

  @doc "Display name for a `StageParticipation` — the team name, or the player's full name. Used in notification payloads and everywhere a fixture participant renders."
  def participant_name(%StageParticipation{player_id: nil} = participation) do
    Repo.preload(participation, :team).team.name
  end

  def participant_name(%StageParticipation{} = participation) do
    player = Repo.preload(participation, :player).player
    "#{player.first_name} #{player.last_name}"
  end

  @doc """
  A player's upcoming (no result yet) fixtures — individually, or via their
  team for Team-category — most imminent first. Backs player-facing
  `FixturesLive`.
  """
  def upcoming_fixtures_for_player(player_id) do
    Fixture
    |> where([f], is_nil(f.result_id))
    |> where([f], f.id in subquery(fixture_ids_for_player_query(player_id)))
    |> order_by(asc: :scheduled_at)
    |> preload([
      :venue,
      participant_a: [:player, :team, :stage],
      participant_b: [:player, :team, :stage]
    ])
    |> Repo.all()
  end

  defp fixture_ids_for_player_query(player_id) do
    participation_ids = participation_ids_for_player_query(player_id)

    from f in Fixture,
      where:
        f.participant_a_id in subquery(participation_ids) or
          f.participant_b_id in subquery(participation_ids),
      select: f.id
  end

  # Shared by upcoming_fixtures_for_player/1, player_has_match_result?/1, and
  # player_has_pending_fixtures?/1 — the StageParticipation(s) representing
  # `player_id`, individually or via their team.
  defp participation_ids_for_player_query(player_id) do
    from p in StageParticipation,
      where: p.player_id == ^player_id or p.team_id in subquery(player_team_id_query(player_id)),
      select: p.id
  end

  defp player_team_id_query(player_id) do
    from p in Cuevolution.Accounts.Player,
      where: p.id == ^player_id and not is_nil(p.team_id),
      select: p.team_id
  end

  ## Match Results & Cuevo Points (spec 008)

  @doc """
  Records the result of `fixture` (spec 008 FR-001/FR-007). Rejects a
  duplicate result via `match_results`' `unique_index(:fixture_id)`. When
  the fixture's category is `"team"`, locks both participants' team rosters
  (`Teams.lock_roster/1`) in the same transaction — per spec 005, the
  freeze applies once a team has at least one recorded match result.

  `attrs`: `%{"winner_participation_id" => id, "score" => map | nil}`.
  """
  def record_result(%Fixture{} = fixture, %Admin{} = admin, attrs) do
    fixture = Repo.preload(fixture, [:participant_a, :participant_b])

    result_attrs = %{
      fixture_id: fixture.id,
      winner_participation_id:
        attrs["winner_participation_id"] || attrs[:winner_participation_id],
      score: attrs["score"] || attrs[:score],
      recorded_by_admin_id: admin.id
    }

    Multi.new()
    |> Multi.insert(:result, MatchResult.create_changeset(%MatchResult{}, result_attrs))
    |> Multi.update(:fixture, fn %{result: result} ->
      Fixture.result_changeset(fixture, result.id)
    end)
    |> Multi.run(:roster_lock, fn _repo, _changes -> lock_rosters_if_team(fixture) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, :result, changeset, _changes} -> {:error, changeset}
    end
  end

  defp lock_rosters_if_team(%Fixture{participant_a: %{category: "team"} = pa, participant_b: pb}) do
    Teams.lock_roster(pa.team_id)
    Teams.lock_roster(pb.team_id)
    {:ok, nil}
  end

  defp lock_rosters_if_team(%Fixture{}), do: {:ok, nil}

  @doc """
  Corrects an already-recorded `result` (spec 008 FR-009). Snapshots the
  pre-update winner/score into `prior_value` (both on the row and in the
  admin action log) before applying the new value — the caller (LiveView)
  is responsible for surfacing the downstream-advancement warning (US4
  scenario 3), this function does not block the correction.
  """
  def correct_result(%MatchResult{} = result, %Admin{} = admin, attrs) do
    prior_value = %{
      "winner_participation_id" => result.winner_participation_id,
      "score" => result.score
    }

    correction_attrs = %{
      winner_participation_id:
        attrs["winner_participation_id"] || attrs[:winner_participation_id] ||
          result.winner_participation_id,
      score: attrs["score"] || attrs[:score] || result.score,
      prior_value: prior_value
    }

    Multi.new()
    |> Multi.update(:result, MatchResult.correction_changeset(result, correction_attrs))
    |> Multi.run(:log, fn _repo, %{result: updated} ->
      Accounts.log_admin_action("correct_result", admin, updated,
        prior_value: prior_value,
        new_value: %{
          "winner_participation_id" => updated.winner_participation_id,
          "score" => updated.score
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, :result, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Ranked standings for `group` (spec 008 FR-002/FR-003) — wraps
  `StandingsCalculator` with real match data. Applies identically at
  Grassroots and Regional; Circuit/Finals groups don't exist (`round_winners/1`
  is the Circuit/Finals equivalent).
  """
  def group_standings(%Group{} = group) do
    participant_ids =
      Repo.all(
        from gm in GroupMembership,
          where: gm.group_id == ^group.id,
          select: gm.stage_participation_id
      )

    StandingsCalculator.rank(participant_ids, group_matches(group.id))
  end

  @doc """
  The top-N ranked participants of `group`'s standings (spec 006 FR-011/
  FR-012, spec 008 FR-002/FR-003) — N is `Competitions.group_config/2`'s
  `advancer_count` (admin-configurable, default 2), applied at both
  Grassroots and Regional. Fewer entrants than N simply returns all of them.
  """
  def top_advancers(%Group{} = group) do
    n =
      case group_config(group.stage_id, group.category) do
        nil -> 0
        config -> config.advancer_count
      end

    group |> group_standings() |> Enum.take(n)
  end

  defp group_matches(group_id) do
    from(mr in MatchResult,
      join: f in Fixture,
      on: f.id == mr.fixture_id,
      join: r in Round,
      on: r.id == f.round_id,
      where: r.group_id == ^group_id,
      preload: [fixture: [:participant_a, :participant_b]]
    )
    |> Repo.all()
    |> Enum.map(&to_calculator_match/1)
  end

  defp to_calculator_match(%MatchResult{fixture: fixture} = result) do
    {frames_a, frames_b} = frame_tally(result, fixture)

    %{
      winner_id: result.winner_participation_id,
      participant_a_id: fixture.participant_a_id,
      participant_b_id: fixture.participant_b_id,
      frames_won_a: frames_a,
      frames_won_b: frames_b
    }
  end

  defp frame_tally(%MatchResult{} = result, %Fixture{participant_a: %{category: "team"}}) do
    MatchFrame
    |> where([f], f.match_result_id == ^result.id)
    |> Repo.all()
    |> Enum.reduce({0, 0}, fn frame, {a, b} ->
      if frame.winner_player_id == frame.home_player_id, do: {a + 1, b}, else: {a, b + 1}
    end)
  end

  defp frame_tally(%MatchResult{score: nil}, %Fixture{}), do: {0, 0}

  defp frame_tally(%MatchResult{score: score}, %Fixture{}) do
    {Map.get(score, "participant_a_frames", 0), Map.get(score, "participant_b_frames", 0)}
  end

  @doc """
  Winners of every completed fixture in `round` (Circuit/Finals bracket
  progression, spec 008 US3b) — the pool of `StageParticipation`s available
  for the admin to manually pair into the next round's fixtures. Pure
  per-fixture winner lookup, not the `StandingsCalculator` — knockout rounds
  have no group standings.
  """
  def round_winners(%Round{} = round) do
    winner_ids =
      Repo.all(
        from mr in MatchResult,
          join: f in Fixture,
          on: f.id == mr.fixture_id,
          where: f.round_id == ^round.id,
          select: mr.winner_participation_id
      )

    StageParticipation
    |> where([p], p.id in ^winner_ids)
    |> preload([:player, :team])
    |> Repo.all()
  end

  @doc """
  Records Cuevo Points for a participant against `result` (or a specific
  `match_frame_id` for Team per-player points) — spec 008 FR-005/FR-006,
  Circuit stage onward.

  `attrs`: `%{"participant_id" => id, "match_frame_id" => id | nil, "points" => integer}`.
  """
  def record_points(%MatchResult{} = result, %Admin{} = admin, attrs) do
    points_attrs = %{
      participant_id: attrs["participant_id"] || attrs[:participant_id],
      match_result_id: result.id,
      match_frame_id: attrs["match_frame_id"] || attrs[:match_frame_id],
      points: attrs["points"] || attrs[:points],
      recorded_by_admin_id: admin.id
    }

    %CuevoPointsEntry{}
    |> CuevoPointsEntry.create_changeset(points_attrs)
    |> Repo.insert()
    |> broadcast_points_updated()
  end

  @doc "Corrects an already-entered Cuevo Points value (spec 008 FR-010) — snapshots prior_value, logs via `Accounts.log_admin_action/4`."
  def correct_points(%CuevoPointsEntry{} = entry, %Admin{} = admin, attrs) do
    prior_value = %{"points" => entry.points}
    new_points = attrs["points"] || attrs[:points]

    Multi.new()
    |> Multi.update(
      :entry,
      CuevoPointsEntry.correction_changeset(entry, %{points: new_points, prior_value: prior_value})
    )
    |> Multi.run(:log, fn _repo, %{entry: updated} ->
      Accounts.log_admin_action("correct_points", admin, updated,
        prior_value: prior_value,
        new_value: %{"points" => updated.points}
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry}} -> {:ok, entry}
      {:error, :entry, changeset, _changes} -> {:error, changeset}
    end
    |> broadcast_points_updated()
  end

  # First real PubSub usage in this app (spec 009) — a single "standings"
  # topic, not per-category/per-region (simplest design at MVP scale;
  # StandingsLive re-runs its own filtered query on every broadcast rather
  # than the payload carrying pre-filtered data).
  defp broadcast_points_updated({:ok, entry} = result) do
    Phoenix.PubSub.broadcast(
      Cuevolution.PubSub,
      "standings",
      {:points_updated, entry.participant_id}
    )

    result
  end

  defp broadcast_points_updated({:error, _reason} = result), do: result

  @doc "Live SUM of `participant_id`'s Cuevo Points — never cached (spec 008, SC-006: a correction must immediately reflect with no stale double-counting)."
  def points_total(participant_id) do
    Repo.aggregate(
      from(e in CuevoPointsEntry, where: e.participant_id == ^participant_id),
      :sum,
      :points
    ) ||
      0
  end

  @doc "Fixtures with no recorded result yet, most imminent first — ResultEntryLive's Unplayed tab."
  def list_unplayed_fixtures do
    Fixture
    |> where([f], is_nil(f.result_id))
    |> order_by(asc: :scheduled_at)
    |> preload([:venue, participant_a: [:player, :team], participant_b: [:player, :team]])
    |> Repo.all()
  end

  @doc "Fixtures with a recorded result, most recently played first — PointsEntryLive's Played tab."
  def list_played_fixtures do
    Fixture
    |> where([f], not is_nil(f.result_id))
    |> order_by(desc: :scheduled_at)
    |> preload([
      :venue,
      [result: :winner_participation],
      participant_a: [:player, :team, :stage],
      participant_b: [:player, :team, :stage]
    ])
    |> Repo.all()
  end

  @doc "Cuevo Points entries already recorded against `match_result_id` — the points-entry form's pre-fill."
  def points_entries_for_result(match_result_id) do
    Repo.all(from e in CuevoPointsEntry, where: e.match_result_id == ^match_result_id)
  end

  @standings_stages ["Circuit", "Finals"]

  @doc """
  Ranked public standings for `category` — participants currently at
  Circuit or Finals, ordered by Cuevo Points descending with a stable
  secondary sort by name for ties. Cuevo Points are only ever earned from
  knockout matches at those two stages (`record_points/3` is only reachable
  from a Circuit/Finals `MatchResult`), and neither stage is region-scoped
  (single bracket per category, spec 006), so this is one overall ranking —
  Grassroots/Regional participants haven't entered the points-earning phase
  yet and are intentionally excluded rather than padding the table with
  permanent zeros.

  Each row also carries `advancing: boolean` — true when the participant is
  ranked (by points, within their *current* stage's own cohort — a Finals
  entrant's rank shouldn't be diluted by every Circuit entrant chasing the
  same table) inside the capacity the admin set for the next stage
  (`StageCapacityConfig`, e.g. "top 64 males advance Circuit → Finals").
  Finals has no next stage, so its entrants are never marked advancing.
  """
  def standings_for_category(category) do
    points = points_by_participant()
    win_loss = win_loss_by_participant()

    StageParticipation
    |> join(:inner, [p], s in assoc(p, :stage))
    |> where([p, s], p.category == ^category and s.name in ^@standings_stages)
    |> preload([:player, :team, :region, :stage])
    |> Repo.all()
    |> Enum.map(fn participation ->
      stats = Map.get(win_loss, participation.id, %{played: 0, won: 0})

      %{
        id: participation.id,
        name: participant_name(participation),
        initials: participant_initials(participation),
        region: participation.region.name,
        stage: participation.stage.name,
        stage_id: participation.stage_id,
        played: stats.played,
        won: stats.won,
        lost: stats.played - stats.won,
        points: Map.get(points, participation.id, 0)
      }
    end)
    |> mark_advancing(category)
    |> Enum.sort_by(&{-&1.points, &1.name})
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> row |> Map.put(:rank, rank) |> Map.delete(:stage_id) end)
  end

  defp mark_advancing(rows, category) do
    caps =
      rows
      |> Enum.map(& &1.stage_id)
      |> Enum.uniq()
      |> Map.new(&{&1, next_stage_capacity(&1, category)})

    rows
    |> Enum.group_by(& &1.stage_id)
    |> Enum.flat_map(fn {stage_id, stage_rows} ->
      cap = Map.fetch!(caps, stage_id)

      stage_rows
      |> Enum.sort_by(&{-&1.points, &1.name})
      |> Enum.with_index(1)
      |> Enum.map(fn {row, stage_rank} ->
        Map.put(row, :advancing, not is_nil(cap) and stage_rank <= cap)
      end)
    end)
  end

  defp next_stage_capacity(stage_id, category) do
    with %Stage{} = stage <- Repo.get(Stage, stage_id),
         %Stage{} = next <- next_stage(stage),
         %StageCapacityConfig{capacity_limit: limit} <- capacity_config(next.id, category) do
      limit
    else
      _ -> nil
    end
  end

  defp points_by_participant do
    CuevoPointsEntry
    |> group_by([e], e.participant_id)
    |> select([e], {e.participant_id, sum(e.points)})
    |> Repo.all()
    |> Map.new()
  end

  defp win_loss_by_participant do
    MatchResult
    |> join(:inner, [mr], f in Fixture, on: f.id == mr.fixture_id)
    |> select([mr, f], {f.participant_a_id, f.participant_b_id, mr.winner_participation_id})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {a_id, b_id, winner_id}, acc ->
      acc
      |> tally_result(a_id, winner_id == a_id)
      |> tally_result(b_id, winner_id == b_id)
    end)
  end

  defp tally_result(acc, participant_id, won?) do
    Map.update(
      acc,
      participant_id,
      %{played: 1, won: if(won?, do: 1, else: 0)},
      fn stat -> %{played: stat.played + 1, won: stat.won + if(won?, do: 1, else: 0)} end
    )
  end

  defp participant_initials(%StageParticipation{player_id: nil} = participation) do
    participation.team.name
    |> String.split(" ", trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp participant_initials(%StageParticipation{} = participation) do
    [participation.player.first_name, participation.player.last_name]
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  @doc """
  Whether `player_id` (individually, or via their team) has a recorded
  `MatchResult` (spec 003 US3/FR-008) — the region-lock check. Deliberately
  checks *played* matches, not scheduled fixtures (spec 003's resolved
  ambiguity): a player with fixtures but no results yet can still change
  region.
  """
  def player_has_match_result?(player_id) do
    participation_ids = participation_ids_for_player_query(player_id)

    MatchResult
    |> join(:inner, [mr], f in Fixture, on: f.id == mr.fixture_id)
    |> where(
      [mr, f],
      f.participant_a_id in subquery(participation_ids) or
        f.participant_b_id in subquery(participation_ids)
    )
    |> Repo.exists?()
  end

  @doc """
  Whether `player_id` (individually, or via their team) has a fixture with
  no recorded result yet (spec 010 US2/FR-007) — the anonymize
  pending-fixture warning.
  """
  def player_has_pending_fixtures?(player_id) do
    participation_ids = participation_ids_for_player_query(player_id)

    Fixture
    |> where([f], is_nil(f.result_id))
    |> where(
      [f],
      f.participant_a_id in subquery(participation_ids) or
        f.participant_b_id in subquery(participation_ids)
    )
    |> Repo.exists?()
  end
end
