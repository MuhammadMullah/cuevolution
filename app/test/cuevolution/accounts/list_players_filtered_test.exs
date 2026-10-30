defmodule Cuevolution.Accounts.ListPlayersFilteredTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts

  describe "list_players_filtered/1" do
    test "with no filters, returns all players" do
      insert_list(3, :player)

      assert length(Accounts.list_players_filtered(%{})) == 3
    end

    test "filters by region_id" do
      region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

      player_a = insert(:player, region_id: region_a.id)
      _player_b = insert(:player, region_id: region_b.id)

      results = Accounts.list_players_filtered(%{region_id: region_a.id})

      assert [found] = results
      assert found.id == player_a.id
    end

    test "filters by category (gender)" do
      male = insert(:player, gender: "male")
      _female = insert(:player, gender: "female")

      results = Accounts.list_players_filtered(%{category: "male"})

      assert [found] = results
      assert found.id == male.id
    end

    test "filters by username substring, case-insensitively" do
      target = insert(:player, username: "SpecialPlayer")
      _other = insert(:player, username: "someoneelse")

      results = Accounts.list_players_filtered(%{search: "special"})

      assert [found] = results
      assert found.id == target.id
    end

    test "filters by name as well as username" do
      target =
        insert(:player, first_name: "Martin", last_name: "Mwangi", username: "Lesta")

      _other = insert(:player, first_name: "Jeff", last_name: "Kibet", username: "Blackmamba")

      for term <- ["Martin", "Mwangi", "Martin Mwangi", "Mwangi Martin", "martin mwangi", "Lesta"] do
        assert [found] = Accounts.list_players_filtered(%{search: term}),
               "expected #{term} to match exactly one player"

        assert found.id == target.id
      end
    end

    test "ignores the @ the console prints in front of a username" do
      target = insert(:player, username: "MAS")

      for term <- ["MAS", "@MAS", "mas", " @MAS "] do
        assert [found] = Accounts.list_players_filtered(%{search: term})
        assert found.id == target.id
      end
    end

    test "still matches usernames that contain @ themselves" do
      bk = insert(:player, username: "Bk@123")
      vans = insert(:player, username: "@Vans01")

      for {term, expected} <- [
            {"Bk@123", bk},
            {"@Bk@123", bk},
            {"BK@123", bk},
            {"@Vans01", vans},
            {"Vans01", vans},
            {"@@Vans01", vans}
          ] do
        assert [found] = Accounts.list_players_filtered(%{search: term}),
               "expected #{term} to match exactly one player"

        assert found.id == expected.id
      end
    end

    test "treats a blank term as no filter" do
      insert_list(3, :player)

      for term <- [nil, "", "   "] do
        assert length(Accounts.list_players_filtered(%{search: term})) == 3
      end
    end

    test "matches LIKE metacharacters literally" do
      target = insert(:player, first_name: "Fifty", last_name: "Percent%")
      _other = insert(:player, first_name: "Other", last_name: "Player")

      assert [found] = Accounts.list_players_filtered(%{search: "Percent%"})
      assert found.id == target.id
    end

    test "filters by stage_id via an indexed query, without loading every participation" do
      stage_a = build(:stage)
      stage_b = build(:stage)
      player_in_a = insert(:player)
      player_in_b = insert(:player)

      insert(:stage_participation, player_id: player_in_a.id, stage_id: stage_a.id)
      insert(:stage_participation, player_id: player_in_b.id, stage_id: stage_b.id)

      results = Accounts.list_players_filtered(%{stage_id: stage_a.id})

      assert [found] = results
      assert found.id == player_in_a.id
    end

    test "combines multiple filters" do
      region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "central")
      other_region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")
      match = insert(:player, region_id: region.id, gender: "female", username: "combofilter")

      _wrong_region =
        insert(:player, region_id: other_region.id, gender: "female", username: "combofilter2")

      results =
        Accounts.list_players_filtered(%{
          region_id: region.id,
          category: "female",
          search: "combo"
        })

      assert [found] = results
      assert found.id == match.id
    end

    test "preloads region without N+1 queries" do
      insert_list(5, :player)

      {queries, _result} =
        with_query_count(fn -> Accounts.list_players_filtered(%{}) end)

      # One query for players + one query for the region preload = 2 total,
      # regardless of player count.
      assert queries == 2
    end
  end

  defp with_query_count(fun) do
    test_pid = self()
    counter = :counters.new(1, [])

    handler = fn _event, _measurements, _metadata, _config ->
      # Telemetry handlers are global — without this guard, queries from
      # other concurrently-running async tests would inflate this count.
      if self() == test_pid, do: :counters.add(counter, 1, 1)
    end

    handler_id = "query-counter-test-#{inspect(test_pid)}"
    :telemetry.attach(handler_id, [:cuevolution, :repo, :query], handler, nil)

    result = fun.()

    :telemetry.detach(handler_id)

    {:counters.get(counter, 1), result}
  end
end
