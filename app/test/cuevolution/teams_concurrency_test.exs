defmodule Cuevolution.TeamsConcurrencyTest do
  # Spawns real processes hitting the same DB connection concurrently, so the
  # sandbox needs shared mode (DataCase enables that automatically for
  # async: false).
  use Cuevolution.DataCase, async: false

  alias Cuevolution.Teams

  test "concurrent create_team calls for the same player: exactly one succeeds" do
    captain = insert(:player)

    results =
      1..5
      |> Task.async_stream(fn i -> Teams.create_team(captain, %{"name" => "Team #{i}"}) end,
        max_concurrency: 5,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &(&1 == {:error, :already_on_a_team}))

    assert successes == 1
    assert failures == 4
  end

  test "concurrent add_player_to_roster/2 calls adding the same player to different teams: exactly one succeeds" do
    player = insert(:player)
    teams = for _ <- 1..5, do: insert(:team)

    results =
      teams
      |> Task.async_stream(fn team -> Teams.add_player_to_roster(team, player) end,
        max_concurrency: 5,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &(&1 == {:error, :already_on_a_team}))

    assert successes == 1
    assert failures == 4
  end
end
