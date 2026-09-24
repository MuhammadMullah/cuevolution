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
  alias Cuevolution.Competitions.Draw
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
  alias Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications
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

  @doc "Sets the stage-wide Grassroots completion deadline."
  def set_grassroots_deadline(%Admin{} = admin, deadline) do
    cond do
      not Admin.can?(admin, :manage_stages) ->
        {:error, :unauthorized}

      not is_nil(deadline) and not match?(%Date{}, deadline) ->
        {:error, :invalid_date}

      true ->
        grassroots_stage()
        |> Stage.changeset(%{completion_deadline: deadline})
        |> Repo.update()
    end
  end

  @doc "The stage immediately after `stage` in pipeline order, or `nil` if `stage` is Finals."
  def next_stage(%Stage{order: order}) do
    Repo.one(from s in Stage, where: s.order == ^(order + 1))
  end

  @doc "The first stage in pipeline order — every new player/team enters here (spec 006)."
  def grassroots_stage do
    Repo.one!(from s in Stage, where: s.order == 1)
  end

  @doc "Recent verified and walkover fixtures for a player, including Grassroots deadline results."
  def recent_results_for_player(player_id) do
    participant_ids =
      from sp in StageParticipation,
        where: sp.player_id == ^player_id,
        select: sp.id

    from(f in Fixture,
      join: r in Round,
      on: r.id == f.round_id,
      join: mr in MatchResult,
      on: mr.fixture_id == f.id,
      where:
        f.status in ["verified", "walkover"] and
          (f.participant_a_id in subquery(participant_ids) or
             f.participant_b_id in subquery(participant_ids)),
      order_by: [desc: f.updated_at],
      limit: 20,
      preload: [
        :result,
        participant_a: :player,
        participant_b: :player,
        round: :stage
      ]
    )
    |> Repo.all()
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
    |> Enum.filter(&Accounts.tournament_eligible?/1)
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
    |> Enum.filter(&Teams.tournament_eligible_team?/1)
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
    |> Multi.run(:eligibility_check, fn repo, _changes ->
      if eligible_for_tournament?(repo, participation),
        do: {:ok, nil},
        else: {:error, :registration_closed}
    end)
    |> Multi.run(:capacity_check, fn repo, _changes ->
      check_and_claim_capacity(repo, stage_id, participation.category)
    end)
    |> Multi.update(:participation, fn _changes ->
      StageParticipation.changeset(participation, %{stage_id: stage_id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{participation: participation}} ->
        {:ok, participation}

      {:error, :eligibility_check, :registration_closed, _changes} ->
        {:error, :registration_closed}

      {:error, :capacity_check, :capacity_exceeded, _changes} ->
        {:error, :capacity_exceeded}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
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

  If `participation` belongs to a team, this also locks that team's roster
  (`Teams.lock_roster/1`) in the same transaction — a team is "drawn" the
  moment it's placed in a group, strictly before any `Fixture` can exist for
  it, so this is the earliest point a captain should lose the ability to
  add/remove players (spec 005's roster freeze moved here from
  first-recorded-result; see `Teams.check_not_frozen/2`).
  """
  def assign_to_group(%StageParticipation{category: category}, %Group{category: group_category})
      when category != group_category do
    {:error, :category_mismatch}
  end

  def assign_to_group(%StageParticipation{} = participation, %Group{} = group) do
    if published_draw_group?(group) do
      {:error, :draw_published}
    else
      do_assign_to_group(participation, group)
    end
  end

  defp do_assign_to_group(participation, group) do
    Multi.new()
    |> Multi.run(:eligibility_check, fn repo, _changes ->
      if eligible_for_tournament?(repo, participation),
        do: {:ok, nil},
        else: {:error, :registration_closed}
    end)
    |> Multi.insert(
      :membership,
      GroupMembership.changeset(%GroupMembership{}, %{
        group_id: group.id,
        stage_participation_id: participation.id
      })
    )
    |> Multi.run(:roster_lock, fn _repo, _changes -> lock_roster_if_team(participation) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        {:ok, membership}

      {:error, :eligibility_check, :registration_closed, _changes} ->
        {:error, :registration_closed}

      {:error, :membership, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp published_draw_group?(%Group{draw_id: nil}), do: false

  defp published_draw_group?(%Group{draw_id: draw_id}) do
    case Repo.get(Draw, draw_id) do
      %Draw{state: "published"} -> true
      _ -> false
    end
  end

  defp eligible_for_tournament?(repo, %StageParticipation{player_id: player_id, team_id: nil}) do
    repo.exists?(
      from p in Player,
        where: p.id == ^player_id and p.inserted_at < ^Accounts.tournament_registration_cutoff()
    )
  end

  defp eligible_for_tournament?(repo, %StageParticipation{team_id: team_id, player_id: nil}) do
    not repo.exists?(
      from p in Player,
        where:
          p.team_id == ^team_id and
            p.inserted_at >= ^Accounts.tournament_registration_cutoff()
    )
  end

  defp lock_roster_if_team(%StageParticipation{team_id: nil}), do: {:ok, nil}

  defp lock_roster_if_team(%StageParticipation{team_id: team_id}) do
    Teams.lock_roster(team_id)
    {:ok, nil}
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

  @doc """
  Groups belonging to a specific `draw_id`, in name order — narrower than
  `list_groups/3`: a redraw creates a fresh `Draw` without deleting the
  superseded one's groups, so listing by stage+venue+category alone would
  mix a still-published old draw's groups in with a fresh one's. The Groups
  page uses this once a `Draw` is on screen, so it only ever shows the
  groups that actual draw produced.
  """
  def list_groups_for_draw(draw_id) do
    Group
    |> where([g], g.draw_id == ^draw_id)
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

  @doc "Returns the existing group configuration or creates the documented defaults on first use."
  def get_or_create_group_config(stage_id, category) do
    case group_config(stage_id, category) do
      %StageGroupConfig{} = config ->
        config

      nil ->
        attrs = %{
          stage_id: stage_id,
          category: category,
          group_size: 8,
          advancer_count: 2,
          target_group_size: 8,
          minimum_group_size: 6,
          minimum_entrants: 4,
          extra_qualifier_count: 0
        }

        case %StageGroupConfig{}
             |> StageGroupConfig.changeset(attrs)
             |> Repo.insert() do
          {:ok, config} -> config
          {:error, _changeset} -> group_config(stage_id, category)
        end
    end
  end

  @doc "Calculates the Grassroots group count and balanced sizes for a venue/category."
  def propose_draw(stage_id, venue_id, category) do
    config = get_or_create_group_config(stage_id, category)
    entrants = draw_entrants(stage_id, venue_id, category)

    case propose_group_sizes(config, length(entrants)) do
      {:ok, proposal} -> {:ok, Map.put(proposal, :entrants, entrants)}
      error -> error
    end
  end

  @doc "Pure group-size calculation used by `propose_draw/3` and its tests."
  def propose_group_sizes(%StageGroupConfig{} = config, entrant_count)
      when entrant_count < config.minimum_entrants,
      do: {:error, :below_minimum}

  def propose_group_sizes(%StageGroupConfig{} = config, entrant_count) do
    group_count = ceil_div(entrant_count, config.target_group_size)

    group_count =
      reduce_to_minimum_group_size(group_count, entrant_count, config.minimum_group_size)

    base_size = div(entrant_count, group_count)
    remainder = rem(entrant_count, group_count)

    sizes =
      for index <- 0..(group_count - 1) do
        base_size + if(index < remainder, do: 1, else: 0)
      end

    {:ok, %{group_count: group_count, sizes: sizes, entrant_count: entrant_count}}
  end

  @doc "Creates a draft draw with the current formula proposal and a reproducibility seed."
  def create_draw(attrs, %Admin{} = admin) when is_map(attrs) do
    if Admin.can?(admin, :manage_groups), do: do_create_draw(attrs), else: {:error, :unauthorized}
  end

  def create_draw(_attrs), do: {:error, :unauthorized}

  defp do_create_draw(attrs) do
    with {:ok, proposal} <- propose_draw(attrs.stage_id, attrs.venue_id, attrs.category) do
      draw_attrs = %{
        stage_id: attrs.stage_id,
        venue_id: attrs.venue_id,
        category: attrs.category,
        state: "draft",
        random_seed: Map.get(attrs, :random_seed, Ecto.UUID.generate()),
        formula_group_count: proposal.group_count
      }

      %Draw{}
      |> Draw.changeset(draw_attrs)
      |> Repo.insert()
    end
  end

  @doc "Deals venue entrants into groups and moves the draw to Previewed."
  def deal_draw(%Draw{} = draw, group_count_override \\ nil)
      when is_nil(group_count_override) or is_integer(group_count_override) do
    do_deal_draw(draw, nil, group_count_override)
  end

  @doc "Deals a draw and records a group-count override against the acting admin."
  def deal_draw(%Draw{} = draw, %Admin{} = admin, group_count_override) do
    do_deal_draw(draw, admin, group_count_override)
  end

  defp do_deal_draw(%Draw{} = draw, admin, group_count_override) do
    draw = Repo.preload(draw, venue: :region)

    with :ok <- authorize_draw_admin(admin),
         {:ok, proposal} <- propose_draw(draw.stage_id, draw.venue_id, draw.category),
         :ok <- validate_draw_override(group_count_override, proposal.entrant_count),
         :ok <- ensure_draw_not_dealt(draw.id) do
      group_count = group_count_override || proposal.group_count
      sizes = balanced_sizes(proposal.entrant_count, group_count)
      entrants = proposal.entrants |> seeded_shuffle(draw.random_seed)
      buckets = deal_entrants(entrants, sizes)

      persist_dealt_draw(draw, admin, group_count_override, buckets)
    end
  end

  defp persist_dealt_draw(draw, admin, group_count_override, buckets) do
    result =
      Multi.new()
      |> Multi.run(:groups, fn repo, _changes -> insert_draw_groups(repo, draw, buckets) end)
      |> Multi.update(:draw, fn _changes ->
        Draw.changeset(draw, %{state: "previewed", group_count_override: group_count_override})
      end)
      |> Repo.transaction()

    with {:ok, %{groups: groups}} <- result,
         :ok <- maybe_log_group_count_override(draw, admin, group_count_override) do
      {:ok, groups}
    end
  end

  defp maybe_log_group_count_override(_draw, nil, nil), do: :ok
  defp maybe_log_group_count_override(_draw, nil, _override), do: {:error, :admin_required}

  defp maybe_log_group_count_override(draw, _admin, override)
       when override == draw.formula_group_count,
       do: :ok

  defp maybe_log_group_count_override(draw, %Admin{} = admin, override) do
    case Accounts.log_admin_action("override_group_count", admin, draw,
           prior_value: %{"group_count" => draw.formula_group_count},
           new_value: %{"group_count" => override}
         ) do
      {:ok, _log} -> :ok
      error -> error
    end
  end

  @doc "Advances a draw through Draft → Previewed → Approved → Published."
  def advance_draw_state(%Draw{} = draw, %Admin{} = admin, target_state) do
    draw = Repo.preload(draw, venue: :region)

    cond do
      not Admin.can?(admin, :manage_groups) ->
        {:error, :unauthorized}

      not valid_draw_transition?(draw.state, target_state) ->
        {:error, :invalid_transition}

      target_state == "published" ->
        publish_draw(draw, admin)

      true ->
        draw
        |> Draw.changeset(%{state: target_state})
        |> Repo.update()
    end
  end

  @doc "Redraws a published draw after confirming no result-bearing fixture exists."
  def redraw(%Draw{} = draw, %Admin{} = admin, reason) when is_binary(reason) do
    cond do
      not Admin.can?(admin, :manage_groups) ->
        {:error, :unauthorized}

      String.trim(reason) == "" ->
        {:error, :reason_required}

      draw_has_results?(draw.id) ->
        {:error, :results_exist}

      true ->
        attrs = %{
          stage_id: draw.stage_id,
          venue_id: draw.venue_id,
          category: draw.category,
          random_seed: Ecto.UUID.generate(),
          formula_group_count: draw.formula_group_count
        }

        case %Draw{} |> Draw.changeset(attrs) |> Repo.insert() do
          {:ok, new_draw} = result ->
            Accounts.log_admin_action("redraw", admin, new_draw,
              prior_value: %{"draw_id" => draw.id},
              new_value: %{"reason" => reason}
            )

            result

          error ->
            error
        end
    end
  end

  @doc """
  The most recently created `Draw` for a stage+venue+category, or `nil` if
  none exists yet. A redraw inserts a new `Draw` row without touching the
  superseded one's `state` (it stays `"published"` for history/dispute
  reproduction), so "most recent" — not "state == published" — is what
  identifies the one currently in play for this scope.
  """
  def latest_draw(stage_id, venue_id, category) do
    Repo.one(
      from d in Draw,
        where: d.stage_id == ^stage_id and d.venue_id == ^venue_id and d.category == ^category,
        order_by: [desc: d.inserted_at],
        limit: 1
    )
  end

  @doc "Generates Berger-method fixtures for all groups in a draw."
  def generate_fixtures_for_draw(%Draw{} = draw) do
    result =
      Multi.new()
      |> Multi.run(:fixtures, fn repo, _changes -> generate_fixtures_for_draw_repo(repo, draw) end)
      |> Repo.transaction()

    case result do
      {:ok, %{fixtures: fixtures}} ->
        enqueue_draw_notifications(draw.id)
        {:ok, fixtures}

      error ->
        error
    end
  end

  defp publish_draw(%Draw{} = draw, admin) do
    result =
      Multi.new()
      |> Multi.update_all(
        :claim,
        from(d in Draw, where: d.id == ^draw.id and d.state == "approved"),
        set: [state: "published", updated_at: NaiveDateTime.utc_now()]
      )
      |> Multi.run(:draw, fn repo, %{claim: {count, _}} ->
        if count == 1 do
          {:ok, repo.get!(Draw, draw.id) |> repo.preload(venue: :region)}
        else
          {:error, :draw_already_published}
        end
      end)
      |> Multi.run(:fixtures, fn repo, %{draw: published} ->
        generate_fixtures_for_draw_repo(repo, published)
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{draw: published, fixtures: fixtures}} ->
        enqueue_draw_notifications(published.id)
        Accounts.log_admin_action("publish_draw", admin, published)
        {:ok, %{draw: published, fixtures: fixtures}}

      error ->
        error
    end
  end

  defp generate_fixtures_for_draw_repo(repo, draw) do
    groups =
      from(g in Group,
        where: g.draw_id == ^draw.id,
        order_by: g.name,
        preload: [
          :venue,
          group_memberships: [stage_participation: [:player, :team]]
        ]
      )
      |> repo.all()

    case groups do
      [] -> {:error, :draw_not_dealt}
      groups -> generate_group_fixtures(repo, draw, groups)
    end
  end

  defp generate_group_fixtures(repo, draw, groups) do
    existing_match_ids =
      repo.all(from f in Fixture, where: not is_nil(f.match_id), select: f.match_id)
      |> MapSet.new()

    Enum.reduce_while(groups, {:ok, [], existing_match_ids}, fn group,
                                                                {:ok, fixtures, match_ids} ->
      participants = Enum.map(group.group_memberships, & &1.stage_participation)

      case insert_group_fixtures(repo, draw, group, participants, match_ids) do
        {:ok, group_fixtures, updated_ids} ->
          {:cont, {:ok, fixtures ++ group_fixtures, updated_ids}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> normalize_fixture_result()
  end

  defp normalize_fixture_result({:ok, fixtures, _match_ids}), do: {:ok, fixtures}
  defp normalize_fixture_result({:ok, fixtures}), do: {:ok, fixtures}
  defp normalize_fixture_result(error), do: error

  defp insert_group_fixtures(repo, draw, group, participants, existing_match_ids) do
    rounds = round_robin_rounds(participants)
    venue_code = venue_code(draw.venue)

    Enum.reduce_while(Enum.with_index(rounds, 1), {:ok, [], existing_match_ids}, fn
      {pairs, round_number}, {:ok, fixtures, match_ids} ->
        round_changeset =
          Round.changeset(%Round{}, %{
            stage_id: draw.stage_id,
            group_id: group.id,
            name: "Round #{round_number}"
          })

        with {:ok, round} <- repo.insert(round_changeset),
             {:ok, new_fixtures, new_match_ids} <-
               insert_round_fixtures(
                 repo,
                 round,
                 draw,
                 group,
                 pairs,
                 round_number,
                 venue_code,
                 match_ids
               ) do
          {:cont, {:ok, fixtures ++ new_fixtures, new_match_ids}}
        else
          error -> {:halt, error}
        end
    end)
  end

  defp insert_round_fixtures(repo, round, draw, group, pairs, round_number, venue_code, match_ids) do
    Enum.reduce_while(Enum.with_index(pairs, 1), {:ok, [], match_ids}, fn
      {{participant_a, participant_b}, match_number}, {:ok, fixtures, ids} ->
        match_id =
          next_match_id(venue_code, draw.category, group.name, round_number, match_number, ids)

        changeset =
          Fixture.auto_generate_changeset(
            %Fixture{},
            %{
              round_id: round.id,
              participant_a_id: participant_a.id,
              participant_b_id: participant_b.id,
              match_id: match_id
            },
            %{participant_a: participant_a, participant_b: participant_b}
          )

        case repo.insert(changeset) do
          {:ok, fixture} ->
            {:cont, {:ok, fixtures ++ [fixture], MapSet.put(ids, match_id)}}

          error ->
            {:halt, error}
        end
    end)
  end

  defp enqueue_draw_notifications(draw_id) do
    %{"draw_id" => draw_id}
    |> DispatchDrawPublishedNotifications.new()
    |> Oban.insert()
  end

  defp draw_entrants(stage_id, venue_id, category) do
    grouped_ids = grouped_draw_participation_ids(stage_id, venue_id, category)

    from(sp in StageParticipation,
      join: p in Player,
      on: p.id == sp.player_id,
      where:
        sp.stage_id == ^stage_id and sp.category == ^category and
          p.preferred_venue_id == ^venue_id and is_nil(p.anonymized_at) and
          p.inserted_at < ^Accounts.tournament_registration_cutoff() and
          sp.id not in subquery(grouped_ids),
      preload: [player: :team]
    )
    |> Repo.all()
  end

  defp grouped_draw_participation_ids(stage_id, venue_id, category) do
    from gm in GroupMembership,
      join: g in Group,
      on: g.id == gm.group_id,
      left_join: d in Draw,
      on: d.id == g.draw_id,
      where:
        g.stage_id == ^stage_id and g.venue_id == ^venue_id and g.category == ^category and
          (is_nil(g.draw_id) or d.state != "published"),
      select: gm.stage_participation_id
  end

  defp reduce_to_minimum_group_size(1, _entrant_count, _minimum), do: 1

  defp reduce_to_minimum_group_size(group_count, entrant_count, minimum) do
    if div(entrant_count, group_count) < minimum do
      reduce_to_minimum_group_size(group_count - 1, entrant_count, minimum)
    else
      group_count
    end
  end

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  @doc "Pure group-size distribution for `entrant_count` split across `group_count` groups — the first `rem(entrant_count, group_count)` groups get one extra entrant. Shared by the actual deal and the Draw Wizard's live group-count preview."
  def balanced_sizes(entrant_count, group_count) do
    base_size = div(entrant_count, group_count)
    remainder = rem(entrant_count, group_count)

    for index <- 0..(group_count - 1) do
      base_size + if(index < remainder, do: 1, else: 0)
    end
  end

  defp seeded_shuffle(list, seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))
    shuffle_with_state(list, state)
  end

  defp shuffle_with_state([], _state), do: []

  defp shuffle_with_state(list, state) do
    {index, state} = :rand.uniform_s(length(list), state)
    {item, rest} = List.pop_at(list, index - 1)
    [item | shuffle_with_state(rest, state)]
  end

  defp seed_tuple(seed) do
    {
      :erlang.phash2({seed, 1}, 4_294_967_295),
      :erlang.phash2({seed, 2}, 4_294_967_295),
      :erlang.phash2({seed, 3}, 4_294_967_295)
    }
  end

  defp deal_entrants(entrants, sizes) do
    Enum.reduce(entrants, Enum.map(sizes, fn size -> %{limit: size, members: []} end), fn entrant,
                                                                                          buckets ->
      candidate_indices =
        buckets
        |> Enum.with_index()
        |> Enum.filter(fn {bucket, _index} ->
          length(bucket.members) < bucket.limit and not same_team?(entrant, bucket.members)
        end)

      {_bucket, index} =
        List.first(candidate_indices) ||
          Enum.find(Enum.with_index(buckets), fn {bucket, _} ->
            length(bucket.members) < bucket.limit
          end)

      List.update_at(buckets, index, fn bucket ->
        %{bucket | members: bucket.members ++ [entrant]}
      end)
    end)
    |> Enum.map(& &1.members)
  end

  defp same_team?(%StageParticipation{player: %{team_id: nil}}, _members), do: false

  defp same_team?(%StageParticipation{player: %{team_id: team_id}}, members) do
    Enum.any?(members, fn %StageParticipation{player: %{team_id: member_team_id}} ->
      team_id == member_team_id
    end)
  end

  defp same_team?(_, _members), do: false

  defp insert_draw_groups(repo, draw, buckets) do
    region_id = draw.venue.region_id

    Enum.reduce_while(Enum.with_index(buckets), {:ok, []}, fn {members, index}, {:ok, groups} ->
      group_name = available_draw_group_name(repo, draw, index)

      group_changeset =
        Group.changeset(%Group{draw_id: draw.id}, %{
          stage_id: draw.stage_id,
          region_id: region_id,
          venue_id: draw.venue_id,
          category: draw.category,
          name: group_name
        })

      with {:ok, group} <- repo.insert(group_changeset),
           {:ok, group} <- insert_group_memberships(repo, group, members) do
        {:cont, {:ok, groups ++ [group]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp available_draw_group_name(repo, draw, index) do
    base_name = "Group #{group_label(index)}"
    available_group_name(repo, draw, base_name, 1)
  end

  defp available_group_name(repo, draw, base_name, suffix) do
    name = if suffix == 1, do: base_name, else: "#{base_name} (#{suffix})"

    exists? =
      repo.exists?(
        from g in Group,
          where:
            g.stage_id == ^draw.stage_id and g.venue_id == ^draw.venue_id and
              g.category == ^draw.category and g.name == ^name
      )

    if exists?, do: available_group_name(repo, draw, base_name, suffix + 1), else: name
  end

  defp insert_group_memberships(repo, group, members) do
    Enum.reduce_while(members, {:ok, group}, fn participant, {:ok, group} ->
      case repo.insert(
             GroupMembership.changeset(%GroupMembership{}, %{
               group_id: group.id,
               stage_participation_id: participant.id
             })
           ) do
        {:ok, _membership} -> {:cont, {:ok, group}}
        error -> {:halt, error}
      end
    end)
  end

  defp round_robin_rounds([]), do: []

  defp round_robin_rounds(participants) do
    players = if rem(length(participants), 2) == 0, do: participants, else: participants ++ [nil]
    [fixed | rotating] = players
    round_count = length(players) - 1

    for round_number <- 0..(round_count - 1) do
      round_players = [fixed | rotate(rotating, round_number)]

      for index <- 0..(div(length(players), 2) - 1),
          participant_a = Enum.at(round_players, index),
          participant_b = Enum.at(round_players, length(players) - 1 - index),
          not is_nil(participant_a) and not is_nil(participant_b),
          do: {participant_a, participant_b}
    end
  end

  defp rotate(list, 0), do: list

  defp rotate(list, count),
    do: Enum.drop(list, rem(count, length(list))) ++ Enum.take(list, rem(count, length(list)))

  defp next_match_id(venue_code, category, group_name, round_number, match_number, ids) do
    category_code = if category == "male", do: "MS", else: "FS"
    group_code = group_code(group_name)
    base = "SP26-#{venue_code}-#{category_code}-#{group_code}-R#{round_number}-M"
    next_match_id(base, match_number, ids)
  end

  defp group_code(group_name) do
    case Regex.run(~r/^Group ([A-Z])/, group_name) do
      [_, code] -> code
      _ -> group_name |> String.replace(~r/[^A-Za-z0-9]/, "") |> String.last() || "A"
    end
  end

  defp next_match_id(base, number, ids) do
    id = base <> to_string(number)
    if MapSet.member?(ids, id), do: next_match_id(base, number + 1, ids), else: id
  end

  defp venue_code(%{name: name}) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 5)
  end

  defp group_label(index) when index < 26, do: <<?A + index::utf8>>
  defp group_label(index), do: "G#{index + 1}"

  defp authorize_draw_admin(nil), do: :ok

  defp authorize_draw_admin(%Admin{} = admin),
    do: if(Admin.can?(admin, :manage_groups), do: :ok, else: {:error, :unauthorized})

  defp validate_draw_override(nil, _entrant_count), do: :ok

  defp validate_draw_override(group_count, entrant_count)
       when group_count > 0 and group_count <= entrant_count, do: :ok

  defp validate_draw_override(_group_count, _entrant_count), do: {:error, :invalid_group_count}

  defp ensure_draw_not_dealt(draw_id) do
    if Repo.exists?(from g in Group, where: g.draw_id == ^draw_id),
      do: {:error, :already_dealt},
      else: :ok
  end

  defp valid_draw_transition?(from, to),
    do:
      %{"draft" => "previewed", "previewed" => "approved", "approved" => "published"}[from] == to

  defp draw_has_results?(draw_id) do
    Repo.exists?(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        join: group in Group,
        on: group.id == r.group_id,
        where: group.draw_id == ^draw_id and f.status in ["completed", "verified", "walkover"]
    )
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
  page's single combined round picker (spec 007).

  Also preloads `group: [:venue, :region]` — every stage/category can have
  multiple groups, each independently numbering its own rounds "Round 1",
  "Round 2", ..., so the picker's label needs the group (and venue/region)
  to tell two different groups' "Round 1" apart. A bare "{Stage} — {Round}"
  label was ambiguous the moment more than one group existed for a stage,
  which is exactly what the Grassroots auto-draw formula produces routinely.
  """
  def list_rounds do
    Repo.all(
      from r in Round,
        join: s in assoc(r, :stage),
        order_by: [asc: s.order, desc: r.inserted_at],
        preload: [stage: s, group: [:venue, :region]]
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
  Every fixture across every round of `group_id`, ordered by round then
  match number — backs the Groups page's inline "expand a group card, see
  its fixtures" view for auto-drawn Grassroots groups.
  """
  def list_fixtures_for_group(group_id) do
    Fixture
    |> join(:inner, [f], r in Round, on: r.id == f.round_id)
    |> where([f, r], r.group_id == ^group_id)
    |> order_by([f, r], asc: r.inserted_at, asc: f.match_id)
    |> preload(participant_a: [:player, :team], participant_b: [:player, :team])
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

  def enter_fixtures(%Round{} = round, %Admin{} = admin, rows) when is_list(rows) do
    if Admin.can?(admin, :manage_fixtures) do
      enter_fixtures(round, rows)
    else
      Enum.map(rows, fn _row -> {:error, :unauthorized} end)
    end
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

  def update_fixture(%Fixture{} = fixture, %Admin{} = admin, attrs) do
    if Admin.can?(admin, :manage_fixtures) do
      update_fixture(fixture, attrs)
    else
      {:error, :unauthorized}
    end
  end

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
      round: [group: :stage],
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
    if Admin.can?(admin, :record_results) do
      do_record_result(fixture, admin, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp do_record_result(%Fixture{} = fixture, %Admin{} = admin, attrs) do
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
    if Admin.can?(admin, :approve_results) do
      do_correct_result(result, admin, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc "Records the five structured singles frames and moves a scheduled fixture to completed."
  def record_frames(%Fixture{} = fixture, %Admin{} = admin, frame_winners)
      when is_list(frame_winners) do
    if Admin.can?(admin, :record_results) do
      do_record_frames(fixture, admin, frame_winners)
    else
      {:error, :unauthorized}
    end
  end

  defp do_record_frames(%Fixture{status: status}, _admin, _frame_winners)
       when status not in ["scheduled", nil],
       do: {:error, :invalid_fixture_state}

  defp do_record_frames(%Fixture{} = fixture, %Admin{} = admin, frame_winners) do
    fixture = Repo.preload(fixture, participant_a: :player, participant_b: :player)

    with {:ok, winners} <- normalize_frame_winners(frame_winners),
         {:ok, winner_id} <- majority_winner(fixture, winners) do
      frames_a = Enum.count(winners, &(&1 == :a))
      frames_b = length(winners) - frames_a

      result_attrs = %{
        fixture_id: fixture.id,
        winner_participation_id: winner_id,
        score: %{
          "participant_a_frames" => frames_a,
          "participant_b_frames" => frames_b,
          "points_a" => points_for_frames(frames_a, frames_b),
          "points_b" => points_for_frames(frames_b, frames_a)
        },
        recorded_by_admin_id: admin.id
      }

      Multi.new()
      |> Multi.insert(:result, MatchResult.create_changeset(%MatchResult{}, result_attrs))
      |> Multi.run(:frames, fn repo, %{result: result} ->
        insert_structured_frames(repo, result, fixture, winners)
      end)
      |> Multi.update(:fixture, fn %{result: result} ->
        fixture
        |> Ecto.Changeset.change(%{result_id: result.id, status: "completed"})
      end)
      |> Multi.run(:roster_lock, fn _repo, _changes -> lock_rosters_if_team(fixture) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{result: result}} -> {:ok, Repo.preload(result, :match_frames)}
        {:error, :result, changeset, _changes} -> {:error, changeset}
        {:error, :frames, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc "Verifies a completed structured result; only verified Grassroots results enter standings."
  def verify_result(%Fixture{} = fixture, %Admin{} = admin, frame_corrections \\ nil) do
    if Admin.can?(admin, :approve_results) do
      do_verify_result(fixture, admin, frame_corrections)
    else
      {:error, :unauthorized}
    end
  end

  defp do_verify_result(%Fixture{status: "completed"} = fixture, %Admin{} = admin, corrections) do
    fixture = Repo.preload(fixture, [:result, participant_a: :player, participant_b: :player])

    with {:ok, winners} <- optional_frame_corrections(corrections, fixture.result),
         {:ok, correction_attrs} <- correction_result_attrs(fixture, winners) do
      Multi.new()
      |> maybe_replace_structured_frames(fixture, winners)
      |> Multi.update(:result, MatchResult.correction_changeset(fixture.result, correction_attrs))
      |> Multi.update(:fixture, Ecto.Changeset.change(fixture, status: "verified"))
      |> Multi.run(:log, fn _repo, %{fixture: verified} ->
        Accounts.log_admin_action("verify_result", admin, verified)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{fixture: verified}} -> {:ok, Repo.preload(verified, :result)}
        {:error, _step, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  defp do_verify_result(%Fixture{}, _admin, _corrections), do: {:error, :invalid_fixture_state}

  @doc "Moves a scheduled fixture to postponed, recording the required reason in the audit log."
  def postpone_fixture(%Fixture{status: "scheduled"} = fixture, %Admin{} = admin, reason) do
    if Admin.can?(admin, :approve_results) and nonempty_reason?(reason) do
      with {:ok, fixture} <- Repo.update(Ecto.Changeset.change(fixture, status: "postponed")),
           {:ok, _log} <-
             Accounts.log_admin_action("postpone_fixture", admin, fixture,
               new_value: %{reason: reason}
             ) do
        {:ok, fixture}
      end
    else
      if Admin.can?(admin, :approve_results),
        do: {:error, :reason_required},
        else: {:error, :unauthorized}
    end
  end

  def postpone_fixture(%Fixture{}, _admin, _reason), do: {:error, :invalid_fixture_state}

  @doc "Resumes a postponed fixture back to the scheduled state."
  def resume_fixture(%Fixture{status: "postponed"} = fixture, %Admin{} = admin) do
    if Admin.can?(admin, :approve_results) do
      Repo.update(Ecto.Changeset.change(fixture, status: "scheduled"))
    else
      {:error, :unauthorized}
    end
  end

  def resume_fixture(%Fixture{}, _admin), do: {:error, :invalid_fixture_state}

  @doc "Records a single walkover for the participant who was present."
  def record_walkover(
        %Fixture{status: "scheduled"} = fixture,
        %Admin{} = admin,
        present_participant
      ) do
    if Admin.can?(admin, :record_results) do
      do_record_walkover(fixture, admin, present_participant)
    else
      {:error, :unauthorized}
    end
  end

  def record_walkover(%Fixture{}, _admin, _present_participant),
    do: {:error, :invalid_fixture_state}

  defp do_record_walkover(fixture, admin, present_participant) do
    fixture = Repo.preload(fixture, [:participant_a, :participant_b])
    present_id = present_participant_id(present_participant)

    case present_id do
      id when id in [fixture.participant_a_id, fixture.participant_b_id] ->
        absent_id =
          if present_id == fixture.participant_a_id,
            do: fixture.participant_b_id,
            else: fixture.participant_a_id

        score =
          if present_id == fixture.participant_a_id,
            do: %{"participant_a_frames" => 5, "participant_b_frames" => 0},
            else: %{"participant_a_frames" => 0, "participant_b_frames" => 5}

        Multi.new()
        |> Multi.insert(
          :result,
          MatchResult.create_changeset(%MatchResult{}, %{
            fixture_id: fixture.id,
            winner_participation_id: present_id,
            score: Map.put(score, "walkover", true),
            recorded_by_admin_id: admin.id
          })
        )
        |> Multi.update(:fixture, fn %{result: result} ->
          Ecto.Changeset.change(fixture,
            result_id: result.id,
            status: "walkover",
            walkover_kind: "single"
          )
        end)
        |> Multi.run(:log, fn _repo, %{fixture: updated} ->
          Accounts.log_admin_action("record_walkover", admin, updated,
            new_value: %{present_participant_id: present_id, absent_participant_id: absent_id}
          )
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{fixture: updated}} -> {:ok, Repo.preload(updated, :result)}
          {:error, _step, changeset, _changes} -> {:error, changeset}
        end

      _ ->
        {:error, :participant_required}
    end
  end

  @doc "Processes a withdrawal, preserving played matches or converting the remaining schedule to walkovers."
  def process_withdrawal(%StageParticipation{} = participation, %Admin{} = admin) do
    if Admin.can?(admin, :approve_results) do
      do_process_withdrawal(participation, admin)
    else
      {:error, :unauthorized}
    end
  end

  defp do_process_withdrawal(participation, admin) do
    fixtures = withdrawal_fixtures(participation.id)
    played = Enum.count(fixtures, &(&1.status in ["completed", "verified", "walkover"]))
    keep_played = played * 2 >= length(fixtures)

    Multi.new()
    |> Multi.run(:fixtures, fn repo, _changes ->
      if keep_played do
        convert_withdrawal_fixtures(repo, fixtures, participation.id, admin)
      else
        reset_withdrawal_fixtures(repo, fixtures)
      end
    end)
    |> Multi.run(:log, fn _repo, %{fixtures: updated} ->
      Accounts.log_admin_action("process_withdrawal", admin, participation,
        new_value: %{
          played: played,
          total: length(fixtures),
          preserved_played: keep_played,
          converted_fixture_ids: Enum.map(updated, & &1.id)
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{fixtures: fixtures}} -> {:ok, fixtures}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp do_correct_result(%MatchResult{} = result, %Admin{} = admin, attrs) do
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

  defp normalize_frame_winners(winners) when length(winners) != 5,
    do: {:error, :five_frames_required}

  defp normalize_frame_winners(winners) do
    normalized = Enum.map(winners, &normalize_frame_winner/1)

    if Enum.any?(normalized, &is_nil/1),
      do: {:error, :invalid_frame_winner},
      else: {:ok, normalized}
  end

  defp normalize_frame_winner(value) when value in [:a, "a", "participant_a"], do: :a
  defp normalize_frame_winner(value) when value in [:b, "b", "participant_b"], do: :b
  defp normalize_frame_winner(%{"winner" => value}), do: normalize_frame_winner(value)
  defp normalize_frame_winner(%{winner: value}), do: normalize_frame_winner(value)
  defp normalize_frame_winner(_value), do: nil

  defp majority_winner(
         %Fixture{participant_a_id: participant_a_id, participant_b_id: participant_b_id},
         winners
       ) do
    a_wins = Enum.count(winners, &(&1 == :a))

    cond do
      a_wins >= 3 -> {:ok, participant_a_id}
      length(winners) - a_wins >= 3 -> {:ok, participant_b_id}
      true -> {:error, :no_majority}
    end
  end

  defp points_for_frames(5, 0), do: 6
  defp points_for_frames(frames_won, _frames_lost), do: frames_won

  defp insert_structured_frames(repo, result, fixture, winners) do
    Enum.with_index(winners, 1)
    |> Enum.reduce_while({:ok, []}, fn {winner, sequence}, {:ok, inserted} ->
      home_id = fixture.participant_a.player_id
      away_id = fixture.participant_b.player_id
      winner_id = if winner == :a, do: home_id, else: away_id

      attrs = %{
        match_result_id: result.id,
        home_player_id: home_id,
        away_player_id: away_id,
        winner_player_id: winner_id,
        sequence: sequence
      }

      case %MatchFrame{} |> MatchFrame.changeset(attrs) |> repo.insert() do
        {:ok, frame} -> {:cont, {:ok, [frame | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp optional_frame_corrections(nil, _result), do: {:ok, nil}
  defp optional_frame_corrections([], _result), do: {:ok, nil}
  defp optional_frame_corrections(corrections, _result), do: normalize_frame_winners(corrections)

  defp correction_result_attrs(_fixture, nil), do: {:ok, %{}}

  defp correction_result_attrs(fixture, winners) do
    with {:ok, winner_id} <- majority_winner(fixture, winners) do
      frames_a = Enum.count(winners, &(&1 == :a))
      frames_b = length(winners) - frames_a

      {:ok,
       %{
         winner_participation_id: winner_id,
         score: %{
           "participant_a_frames" => frames_a,
           "participant_b_frames" => frames_b,
           "points_a" => points_for_frames(frames_a, frames_b),
           "points_b" => points_for_frames(frames_b, frames_a)
         }
       }}
    end
  end

  defp maybe_replace_structured_frames(multi, _fixture, nil), do: multi

  defp maybe_replace_structured_frames(multi, fixture, winners) do
    Multi.delete_all(
      multi,
      :old_frames,
      from(f in MatchFrame, where: f.match_result_id == ^fixture.result.id)
    )
    |> Multi.run(:replacement_frames, fn repo, _changes ->
      insert_structured_frames(repo, fixture.result, fixture, winners)
    end)
  end

  defp nonempty_reason?(reason), do: is_binary(reason) and String.trim(reason) != ""

  defp present_participant_id(%StageParticipation{id: id}), do: id
  defp present_participant_id(id) when is_binary(id), do: id
  defp present_participant_id(_), do: nil

  defp withdrawal_fixtures(participation_id) do
    Fixture
    |> join(:inner, [f], r in Round, on: r.id == f.round_id)
    |> where(
      [f, _r],
      f.participant_a_id == ^participation_id or f.participant_b_id == ^participation_id
    )
    |> preload([:result, :participant_a, :participant_b])
    |> Repo.all()
  end

  defp convert_withdrawal_fixtures(repo, fixtures, withdrawn_id, admin) do
    Enum.reduce_while(fixtures, {:ok, []}, fn fixture, {:ok, converted} ->
      case convert_withdrawal_fixture(repo, fixture, withdrawn_id, admin) do
        :skip -> {:cont, {:ok, converted}}
        {:ok, updated} -> {:cont, {:ok, [updated | converted]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp convert_withdrawal_fixture(_repo, %Fixture{status: status}, _withdrawn_id, _admin)
       when status != "scheduled",
       do: :skip

  defp convert_withdrawal_fixture(repo, fixture, withdrawn_id, admin) do
    opponent_id =
      if fixture.participant_a_id == withdrawn_id,
        do: fixture.participant_b_id,
        else: fixture.participant_a_id

    result_attrs = %{
      fixture_id: fixture.id,
      winner_participation_id: opponent_id,
      score: withdrawal_score(fixture, opponent_id),
      recorded_by_admin_id: admin.id
    }

    case repo.insert(MatchResult.create_changeset(%MatchResult{}, result_attrs)) do
      {:ok, result} ->
        repo.update(
          Ecto.Changeset.change(fixture,
            result_id: result.id,
            status: "walkover",
            walkover_kind: "single"
          )
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp withdrawal_score(%Fixture{participant_a_id: participant_a_id}, participant_a_id),
    do: %{"participant_a_frames" => 5, "participant_b_frames" => 0, "withdrawal" => true}

  defp withdrawal_score(%Fixture{}, _participant_b_id),
    do: %{"participant_a_frames" => 0, "participant_b_frames" => 5, "withdrawal" => true}

  defp reset_withdrawal_fixtures(repo, fixtures) do
    Enum.reduce_while(fixtures, {:ok, []}, fn fixture, {:ok, reset} ->
      if fixture.result_id do
        repo.delete_all(from f in MatchFrame, where: f.match_result_id == ^fixture.result_id)
        repo.delete_all(from mr in MatchResult, where: mr.id == ^fixture.result_id)
      end

      case repo.update(
             Ecto.Changeset.change(fixture,
               result_id: nil,
               status: "scheduled",
               walkover_kind: nil
             )
           ) do
        {:ok, updated} -> {:cont, {:ok, [updated | reset]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
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

    case Repo.preload(group, :stage).stage.name do
      "Grassroots" ->
        grassroots_group_standings(group)

      _ ->
        StandingsCalculator.rank(participant_ids, group_matches(group.id), cascade: :wins_first)
    end
  end

  @doc "Points-first standings for a Grassroots group, including persisted TD tie overrides."
  def grassroots_group_standings(%Group{} = group) do
    participant_ids =
      Repo.all(
        from gm in GroupMembership,
          where: gm.group_id == ^group.id,
          select: gm.stage_participation_id
      )

    group = Repo.preload(group, :stage)

    if group.stage.name == "Grassroots" do
      StandingsCalculator.rank(participant_ids, group_matches(group.id),
        cascade: :points_first,
        tie_breakers: Enum.chunk_every(group.tie_breakers || [], 2)
      )
    else
      []
    end
  end

  @doc "Persists a TD decision that `participant_a` ranks ahead of `participant_b`."
  def resolve_tie(%Group{} = group, %Admin{} = admin, participant_a, participant_b) do
    if Admin.can?(admin, :manage_groups),
      do: persist_tie_resolution(group, participant_a, participant_b),
      else: {:error, :unauthorized}
  end

  defp persist_tie_resolution(group, participant_a, participant_b) do
    existing = Enum.chunk_every(Repo.get!(Group, group.id).tie_breakers || [], 2)

    if participant_a == participant_b or
         Enum.any?(existing, fn [winner, loser] ->
           winner == participant_b and loser == participant_a
         end) do
      {:error, :invalid_tie_override}
    else
      tie_breakers =
        existing
        |> Enum.reject(fn [winner, loser] ->
          winner == participant_a or loser == participant_b
        end)
        |> Kernel.++([[to_string(participant_a), to_string(participant_b)]])
        |> List.flatten()

      Repo.update(Ecto.Changeset.change(Repo.get!(Group, group.id), tie_breakers: tie_breakers))
    end
  end

  @doc "Ranks non-top-N Grassroots participants across groups by normalized performance."
  def best_of_rest_qualifiers(stage_id, category) do
    groups = Repo.all(from g in Group, where: g.stage_id == ^stage_id and g.category == ^category)
    config = get_or_create_group_config(stage_id, category)
    top_count = config.advancer_count

    groups
    |> Enum.flat_map(fn group ->
      standings = grassroots_group_standings(group)
      top_ids = standings |> Enum.take(top_count) |> MapSet.new(& &1.participant_id)

      Enum.flat_map(standings, &best_rest_row(&1, top_ids, group.id))
    end)
    |> Enum.sort_by(fn row ->
      {-row.points_per_match, -row.frame_diff_per_match, to_string(row.participant_id)}
    end)
    |> Enum.take(config.extra_qualifier_count)
  end

  defp best_rest_row(row, top_ids, group_id) do
    played = row.wins + row.losses

    if played > 0 and not MapSet.member?(top_ids, row.participant_id) do
      [
        Map.merge(row, %{
          matches_played: played,
          points_per_match: row.points / played,
          frame_diff_per_match: row.frame_diff / played,
          group_id: group_id
        })
      ]
    else
      []
    end
  end

  @doc "Advances the reviewed top-N and best-of-rest qualifiers into the next stage."
  def close_grassroots_stage(stage_id, category, %Admin{} = admin, confirmed_ids)
      when is_list(confirmed_ids) do
    with true <- Admin.can?(admin, :manage_groups),
         %Stage{name: "Grassroots"} = stage <- Repo.get(Stage, stage_id),
         next_stage when not is_nil(next_stage) <- next_stage(stage),
         groups <-
           Repo.all(from g in Group, where: g.stage_id == ^stage_id and g.category == ^category),
         config <- get_or_create_group_config(stage_id, category),
         top_ids <-
           Enum.flat_map(groups, fn group ->
             Enum.take(group_standings(group), config.advancer_count)
           end)
           |> Enum.map(& &1.participant_id),
         best_ids <- Enum.map(best_of_rest_qualifiers(stage_id, category), & &1.participant_id),
         expected <- Enum.uniq(top_ids ++ best_ids),
         true <-
           Enum.sort(Enum.map(confirmed_ids, &to_string/1)) ==
             Enum.sort(Enum.map(expected, &to_string/1)) do
      participations = Repo.all(from sp in StageParticipation, where: sp.id in ^expected)

      advance_qualifiers(participations, next_stage)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :stage_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_qualifiers}
    end
  end

  defp advance_qualifiers(participations, next_stage) do
    Enum.reduce_while(participations, {:ok, []}, fn participation, {:ok, advanced} ->
      case advance_to_stage(participation, next_stage) do
        {:ok, advanced_participation} -> {:cont, {:ok, [advanced_participation | advanced]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def grassroots_group_for_player(player_id) do
    group_id =
      Repo.one(
        from gm in GroupMembership,
          join: g in Group,
          on: g.id == gm.group_id,
          join: s in Stage,
          on: s.id == g.stage_id,
          join: sp in StageParticipation,
          on: sp.id == gm.stage_participation_id,
          where: sp.player_id == ^player_id and s.name == "Grassroots",
          select: gm.group_id
      )

    if group_id do
      Repo.get!(Group, group_id)
      |> Repo.preload([:stage, group_memberships: :stage_participation])
    end
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
      where: is_nil(f.match_id) or f.status in ["verified", "walkover"],
      preload: [fixture: [:participant_a, :participant_b]]
    )
    |> Repo.all()
    |> Enum.map(&to_calculator_match/1)
  end

  defp to_calculator_match(%MatchResult{fixture: fixture} = result) do
    {frames_a, frames_b} = frame_tally(result, fixture)
    score = result.score || %{}

    %{
      winner_id: result.winner_participation_id,
      participant_a_id: fixture.participant_a_id,
      participant_b_id: fixture.participant_b_id,
      frames_won_a: frames_a,
      frames_won_b: frames_b,
      points_a: Map.get(score, "points_a"),
      points_b: Map.get(score, "points_b"),
      bonus_a: Map.get(score, "bonus_a"),
      bonus_b: Map.get(score, "bonus_b"),
      status: fixture.status
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
    if Admin.can?(admin, :record_results) do
      do_record_points(result, admin, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp do_record_points(%MatchResult{} = result, %Admin{} = admin, attrs) do
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
    if Admin.can?(admin, :approve_results) do
      do_correct_points(entry, admin, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp do_correct_points(%CuevoPointsEntry{} = entry, %Admin{} = admin, attrs) do
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

  @doc """
  Checks whether a venue already has any draws associated with it.

  A venue cannot be deactivated once it has a scheduled fixture or a Grassroots
  group that has already been paired for play.

  """
  def venue_has_draws?(venue_id) do
    Repo.exists?(from f in Fixture, where: f.venue_id == ^venue_id) or
      Repo.exists?(from g in Group, where: g.venue_id == ^venue_id)
  end
end
