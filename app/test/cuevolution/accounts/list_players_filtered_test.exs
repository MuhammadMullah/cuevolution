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

      results = Accounts.list_players_filtered(%{username: "special"})

      assert [found] = results
      assert found.id == target.id
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
          username: "combo"
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
