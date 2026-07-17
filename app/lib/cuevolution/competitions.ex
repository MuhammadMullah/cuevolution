defmodule Cuevolution.Competitions do
  @moduledoc """
  The Competitions context: the qualification pipeline (spec 006) — stages,
  per-stage/category capacity, stage participations, and grouping/knockout
  brackets — plus draws/fixtures (spec 007). Later specs (008 results/points,
  009 standings) extend this same module.
  """

  import Ecto.Query

  require Logger

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Group
  alias Cuevolution.Competitions.GroupMembership
  alias Cuevolution.Competitions.KnockoutBracket
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
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
  Assigns `participation` to `group` (spec 006 FR-003/FR-004).
  """
  def assign_to_group(%StageParticipation{} = participation, %Group{} = group) do
    %GroupMembership{}
    |> GroupMembership.changeset(%{
      group_id: group.id,
      stage_participation_id: participation.id
    })
    |> Repo.insert()
  end

  @doc "Groups for `stage_id`/`region_id`, with membership count preloaded."
  def list_groups(stage_id, region_id) do
    Group
    |> where([g], g.stage_id == ^stage_id and g.region_id == ^region_id)
    |> order_by(asc: :name)
    |> preload(group_memberships: [stage_participation: [:player, :team]])
    |> Repo.all()
  end

  @doc """
  Participations in `stage_id`/`region_id` not yet in any group for that
  stage — the GroupManagementLive "unassigned" pool.
  """
  def list_unassigned_participations(stage_id, region_id) do
    grouped_ids =
      from(gm in GroupMembership,
        join: g in Group,
        on: g.id == gm.group_id,
        where: g.stage_id == ^stage_id and g.region_id == ^region_id,
        select: gm.stage_participation_id
      )

    StageParticipation
    |> where([p], p.stage_id == ^stage_id and p.region_id == ^region_id)
    |> where([p], p.id not in subquery(grouped_ids))
    |> preload([:player, :team])
    |> Repo.all()
  end

  @doc """
  Creates a group for `stage_id`/`region_id` (spec 006). Grassroots grouping
  produces no bracket (FR-003); Regional grouping auto-creates an empty,
  available `KnockoutBracket` in the same transaction (FR-004).
  """
  def create_group(attrs) do
    changeset = Group.changeset(%Group{}, attrs)

    Multi.new()
    |> Multi.insert(:group, changeset)
    |> Multi.run(:bracket, fn repo, %{group: group} ->
      stage = repo.get!(Stage, group.stage_id)

      if stage.name == "Regional" do
        %KnockoutBracket{}
        |> KnockoutBracket.changeset(%{group_id: group.id})
        |> repo.insert()
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{group: group}} -> {:ok, group}
      {:error, :group, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc "Rounds for `stage_id`, most recently created first — the admin Draws page's round picker."
  def list_rounds_for_stage(stage_id) do
    Repo.all(from r in Round, where: r.stage_id == ^stage_id, order_by: [desc: r.inserted_at])
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
      resolve_participant(repo, round.stage_id, row["category"], row["a_kind"], row["a_id"])
    end)
    |> Multi.run(:participant_b, fn repo, _changes ->
      resolve_participant(repo, round.stage_id, row["category"], row["b_kind"], row["b_id"])
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

  defp resolve_participant(_repo, _stage_id, _category, _kind, nil),
    do: {:error, :participant_required}

  defp resolve_participant(repo, stage_id, category, "player", player_id) do
    find_participant(repo, stage_id, category, player_id: player_id)
  end

  defp resolve_participant(repo, stage_id, category, "team", team_id) do
    find_participant(repo, stage_id, category, team_id: team_id)
  end

  defp find_participant(repo, stage_id, category, clauses) do
    query =
      from p in StageParticipation,
        where: p.stage_id == ^stage_id and p.category == ^category

    query =
      Enum.reduce(clauses, query, fn {field, value}, q ->
        where(q, [p], field(p, ^field) == ^value)
      end)

    case repo.one(query) do
      nil -> {:error, :participant_not_in_stage}
      participation -> {:ok, participation}
    end
  end

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
    participation_ids =
      from p in StageParticipation,
        where:
          p.player_id == ^player_id or p.team_id in subquery(player_team_id_query(player_id)),
        select: p.id

    from f in Fixture,
      where:
        f.participant_a_id in subquery(participation_ids) or
          f.participant_b_id in subquery(participation_ids),
      select: f.id
  end

  defp player_team_id_query(player_id) do
    from p in Cuevolution.Accounts.Player,
      where: p.id == ^player_id and not is_nil(p.team_id),
      select: p.team_id
  end
end
