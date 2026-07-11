defmodule Cuevolution.Seeds.Teams do
  @moduledoc """
  Seeds a handful of teams, each with a roster, drawn from the players
  `Cuevolution.Seeds.Accounts` already created. Idempotent — safe to re-run.
  Depends on `Cuevolution.Seeds.Accounts` having already run.
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team

  @team_count 5
  @roster_size 6
  @team_name_prefix "Seed Team"

  def run do
    already_seeded =
      Repo.aggregate(from(t in Team, where: like(t.name, ^"#{@team_name_prefix}%")), :count)

    if already_seeded >= @team_count do
      IO.puts("Teams already seeded (#{already_seeded}).")
    else
      unrostered_players =
        Repo.all(
          from p in Player,
            where: is_nil(p.team_id) and like(p.username, "seedplayer%"),
            order_by: p.username
        )

      unrostered_players
      |> Enum.chunk_every(@roster_size)
      |> Enum.take(@team_count - already_seeded)
      |> Enum.with_index(already_seeded + 1)
      |> Enum.each(fn {[captain | members], index} -> seed_team(index, captain, members) end)

      IO.puts("Seeded teams.")
    end
  end

  defp seed_team(index, captain, members) do
    case Teams.create_team(captain, %{"name" => "#{@team_name_prefix} #{index}"}) do
      {:ok, team} ->
        Enum.each(members, fn member -> Teams.add_player_to_roster(team, member) end)

      {:error, reason} ->
        IO.warn("Failed to seed team #{index}: #{inspect(reason)}")
    end
  end
end

Cuevolution.Seeds.Teams.run()
