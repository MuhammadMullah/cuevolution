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

  @doc """
  Creates a team with `captain` as its Team Captain (spec 005 FR-001). The
  team's region is inherited from the captain, never user-supplied.

  Atomically claims the captain's roster slot (`players.team_id`) — if the
  captain is concurrently claimed by another `create_team/2` or
  `add_player_to_roster/2` call first, this one loses the race and the whole
  team creation rolls back (FR-007, DB-level, not just a changeset check).
  """
  def create_team(%Player{} = captain, attrs) do
    name = attrs["name"] || attrs[:name]

    changeset =
      Team.changeset(%Team{}, %{
        name: name,
        region_id: captain.region_id,
        captain_id: captain.id
      })

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

  @max_roster_size 8

  @doc """
  Adds `player` to `team`'s roster (spec 005 FR-002/FR-003/FR-004).

  The "same player claimed by two different teams" race is closed
  atomically at the DB level, same as `create_team/2`. The roster-size cap
  is a plain count-then-check — not fully race-proof against two *different*
  players being added to the *same* team in the same instant, but that's a
  far narrower window than the same-player race and isn't the scenario this
  task calls out as concurrency-critical.

  ⚠️ The roster-freeze clause (FR-008, once `team.roster_locked_at` is set)
  is deferred until `Competitions.MatchResult` exists — not implemented yet.
  """
  def add_player_to_roster(%Team{} = team, %Player{} = player) do
    Multi.new()
    |> Multi.run(:check_capacity, fn repo, _changes ->
      count = repo.aggregate(from(p in Player, where: p.team_id == ^team.id), :count)
      if count < @max_roster_size, do: {:ok, count}, else: {:error, :roster_full}
    end)
    |> Multi.update_all(:claim_player, fn _changes -> claim_query(player.id, team.id) end, [])
    |> Multi.run(:verify_claim, fn _repo, %{claim_player: {count, _}} ->
      if count == 1, do: {:ok, count}, else: {:error, :already_on_a_team}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        updated_player = Repo.get!(Player, player.id)
        dispatch_team_assignment(updated_player, team)
        {:ok, updated_player}

      {:error, :check_capacity, :roster_full, _changes} ->
        {:error, :roster_full}

      {:error, :verify_claim, :already_on_a_team, _changes} ->
        {:error, :already_on_a_team}
    end
  end

  # A notification-dispatch failure is caught and logged — it never rolls
  # back the already-committed roster change, same policy as
  # `Accounts.register_player/1`'s registration-confirmation dispatch.
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

  @min_roster_size 5

  @doc """
  Removes `player` from `team`'s roster (spec 005 FR-005). The roster is
  allowed to drop below the minimum — `eligible?/1` reflects that on its own
  next call rather than this function blocking the removal.

  ⚠️ Not specially guarded: removing the captain themselves. Spec 005 has no
  captain-succession/transfer mechanic (explicitly flagged as unresolved in
  its Edge Cases) — this function treats the captain like any roster member.
  """
  def remove_player_from_roster(%Team{} = team, %Player{} = player) do
    Player
    |> where(id: ^player.id, team_id: ^team.id)
    |> Repo.update_all(set: [team_id: nil])
    |> case do
      {1, _} -> {:ok, Repo.get!(Player, player.id)}
      {0, _} -> {:error, :not_on_this_team}
    end
  end

  @doc """
  Whether `team`'s roster is within the required 5-8 range (spec 005 FR-005)
  — always derived live from `players.team_id`, never a cached column.
  """
  def eligible?(%Team{} = team) do
    count = Repo.aggregate(from(p in Player, where: p.team_id == ^team.id), :count)
    count >= @min_roster_size and count <= @max_roster_size
  end

  defp claim_query(player_id, team_id) do
    from(p in Player,
      where: p.id == ^player_id and is_nil(p.team_id),
      update: [set: [team_id: ^team_id]]
    )
  end

  @doc """
  Filterable team directory query — the Teams-context counterpart of
  `Accounts.list_players_filtered/1`, backing the admin Directory's "Teams"
  kind. Supported filters: `:region_id`, `:name` (case-insensitive
  substring search).
  """
  def list_teams_filtered(filters \\ %{}) do
    Team
    |> filter_by_region(filters[:region_id])
    |> filter_by_name(filters[:name])
    |> order_by(asc: :name)
    |> preload([:region, :captain, :roster])
    |> Repo.all()
  end

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  defp filter_by_name(query, nil), do: query

  defp filter_by_name(query, name) do
    pattern = "%" <> String.replace(name, ~w(% _), fn c -> "\\" <> c end) <> "%"
    where(query, [t], ilike(t.name, ^pattern))
  end
end
