defmodule Cuevolution.Seeds.Teams do
  @moduledoc """
  Seeds team rosters drawn from the players `Cuevolution.Seeds.Accounts`
  already created. Idempotent — safe to re-run. Depends on
  `Cuevolution.Seeds.Accounts` having already run.

  Rosters are built per-region (captain and members always share a region)
  and interleaved round-robin across regions so every region ends up with
  the same number of teams. Only a minority of players end up rostered —
  most stay teamless, matching a sport where most competitors play as
  individuals and teams are an optional overlay.
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team

  @team_count 200
  @roster_size 6
  @team_name_prefix "Seed Team"
  @seed_concurrency 8

  def run do
    already_seeded =
      Repo.aggregate(from(t in Team, where: like(t.name, ^"#{@team_name_prefix}%")), :count)

    if already_seeded >= @team_count do
      IO.puts("Teams already seeded (#{already_seeded}).")
    else
      rosters =
        from(p in Player,
          where: is_nil(p.team_id) and like(p.username, "seedplayer%"),
          order_by: [p.region_id, p.username]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.region_id)
        |> Map.values()
        |> Enum.map(&Enum.chunk_every(&1, @roster_size))
        |> round_robin()
        |> Enum.take(@team_count - already_seeded)

      errors =
        rosters
        |> Enum.with_index(already_seeded + 1)
        |> Task.async_stream(
          fn {[captain | members], index} -> seed_team(index, captain, members) end,
          max_concurrency: @seed_concurrency,
          timeout: :infinity,
          ordered: false
        )
        |> Enum.count(fn {:ok, result} -> result != :ok end)

      IO.puts("Seeded #{length(rosters)} team(s) (#{errors} failure(s)).")
    end
  end

  # Takes one chunk from every still-non-empty region list per round, so
  # regions are interleaved fairly instead of exhausting one region's teams
  # before moving to the next.
  defp round_robin(lists) do
    case Enum.reject(lists, &(&1 == [])) do
      [] ->
        []

      non_empty ->
        heads = Enum.map(non_empty, &hd/1)
        tails = Enum.map(non_empty, &tl/1)
        heads ++ round_robin(tails)
    end
  end

  defp seed_team(index, captain, members) do
    case Teams.create_team(captain, %{"name" => "#{@team_name_prefix} #{index}"}) do
      {:ok, team} ->
        Enum.each(members, fn member -> Teams.add_player_to_roster(team, member) end)
        :ok

      {:error, reason} ->
        IO.warn("Failed to seed team #{index}: #{inspect(reason)}")
        :error
    end
  end
end

Cuevolution.Seeds.Teams.run()
