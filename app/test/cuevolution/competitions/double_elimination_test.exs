defmodule Cuevolution.Competitions.DoubleEliminationTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.DoubleElimination, as: DE

  defp men, do: DE.build(Enum.to_list(1..128))
  defp by_code(%{fixtures: f}), do: Map.new(f, &{&1.code, &1})
  defp round(%{rounds: r}, code), do: Enum.find(r, &(&1.code == code))

  describe "seed_order/1" do
    test "reproduces the sample draw's Winners R1 pairings exactly" do
      # Straight off the 2026 sample draw sheet, W1-1 through W1-12.
      expected = [
        {1, 128},
        {64, 65},
        {32, 97},
        {33, 96},
        {16, 113},
        {49, 80},
        {17, 112},
        {48, 81},
        {8, 121},
        {57, 72},
        {25, 104},
        {40, 89}
      ]

      assert DE.seed_pairs(128) |> Enum.take(12) == expected
    end

    test "every pair sums to size + 1, and every seed appears once" do
      for size <- [8, 16, 32, 64, 128] do
        order = DE.seed_order(size)
        assert Enum.sort(order) == Enum.to_list(1..size)

        for {a, b} <- DE.seed_pairs(size) do
          assert a + b == size + 1
        end
      end
    end
  end

  describe "round structure" do
    test "a 128 field produces the sample draw's match counts" do
      bracket = men()
      counts = Map.new(bracket.rounds, &{&1.code, &1.matches})

      assert counts["W1"] == 64
      assert counts["W2"] == 32
      assert counts["L1"] == 32
      assert counts["L2"] == 32
      assert counts["R64"] == 32
      assert counts["R32"] == 16
      assert counts["R16"] == 8
      assert counts["QF"] == 4
      assert counts["SF"] == 2
      assert counts["F"] == 1

      assert Enum.sum(Enum.map(bracket.rounds, & &1.matches)) == 223
      assert length(bracket.fixtures) == 223
    end

    test "a 64 field halves it — the ladies' bracket" do
      bracket = DE.build(Enum.to_list(1..64))
      counts = Map.new(bracket.rounds, &{&1.code, &1.matches})

      assert counts["W1"] == 32
      assert counts["W2"] == 16
      assert counts["L1"] == 16
      assert counts["L2"] == 16
      assert counts["R32"] == 16
      refute Map.has_key?(counts, "R64")
      assert Enum.sum(Enum.map(bracket.rounds, & &1.matches)) == 111
    end

    test "55 ladies play the 93 matches the format document predicts" do
      bracket = DE.build(Enum.to_list(1..55), category: "female", byes: :random, rng: 42)

      # 111 slots in a 64 bracket, less 9 byes and the 9 losers'-bracket
      # walkovers those byes leave behind, is 93 matches actually played.
      incoming =
        bracket.fixtures
        |> Enum.flat_map(fn fx -> Enum.filter([fx.winner_to, fx.loser_to], & &1) end)
        |> Enum.frequencies_by(fn {code, _side} -> code end)

      byes = Enum.count(bracket.fixtures, & &1.bye)

      walkovers =
        Enum.count(bracket.fixtures, fn fx ->
          fx.round_code == "L1" and Map.get(incoming, fx.code, 0) < 2
        end)

      assert byes == 9
      assert walkovers == 9
      assert length(bracket.fixtures) - byes - walkovers == 93
    end

    test "men's race lengths follow the official format sheet" do
      # "Race to 6 all through · Losers side race to 5 · Final race to 7"
      bracket = men()
      assert round(bracket, "W1").race_to == 6
      assert round(bracket, "W2").race_to == 6
      assert round(bracket, "L1").race_to == 5
      assert round(bracket, "L2").race_to == 5
      assert round(bracket, "R64").race_to == 6
      assert round(bracket, "R16").race_to == 6
      assert round(bracket, "QF").race_to == 6
      assert round(bracket, "SF").race_to == 6
      assert round(bracket, "F").race_to == 7
    end

    test "ladies' race lengths follow the official format sheet" do
      # "Race to 4 all through · Losers side race to 3 · Final race to 5"
      bracket = DE.build(Enum.to_list(1..64), category: "female")
      assert round(bracket, "W1").race_to == 4
      assert round(bracket, "W2").race_to == 4
      assert round(bracket, "L1").race_to == 3
      assert round(bracket, "L2").race_to == 3
      assert round(bracket, "R32").race_to == 4
      assert round(bracket, "QF").race_to == 4
      assert round(bracket, "SF").race_to == 4
      assert round(bracket, "F").race_to == 5
    end

    test "races can be overridden per draw without editing the module" do
      flat = DE.build(Enum.to_list(1..128), races: %{losers: 6, final: 9})
      assert round(flat, "L1").race_to == 6
      assert round(flat, "F").race_to == 9
      assert round(flat, "W1").race_to == 6
    end
  end

  describe "routing" do
    test "winners and losers from Winners R1 land in matching slots" do
      f = by_code(men())

      assert f["W1-1"].winner_to == {"W2-1", :a}
      assert f["W1-2"].winner_to == {"W2-1", :b}
      assert f["W1-1"].loser_to == {"L1-1", :a}
      assert f["W1-2"].loser_to == {"L1-1", :b}
      assert f["W1-63"].winner_to == {"W2-32", :a}
      assert f["W1-64"].loser_to == {"L1-32", :b}
    end

    test "the crossover is mirrored, as in the sample draw" do
      f = by_code(men())

      # Sample: "L2-1  L1-1 winner v W2-32 loser", "L2-17  L1-17 winner v W2-16 loser".
      # The pairing is the sample's; the slots put whoever arrives from the
      # winners' side on top, so a crossover card always reads the same way.
      assert f["W2-32"].loser_to == {"L2-1", :a}
      assert f["W2-16"].loser_to == {"L2-17", :a}
      assert f["L1-1"].winner_to == {"L2-1", :b}
      assert f["L1-17"].winner_to == {"L2-17", :b}
    end

    test "the knockout is offset by half a round, as in the sample draw" do
      f = by_code(men())

      # Sample: "R64-1  W2-1 winner v L2-17 winner", "R64-17 W2-17 winner v L2-1 winner"
      assert f["W2-1"].winner_to == {"R64-1", :a}
      assert f["L2-17"].winner_to == {"R64-1", :b}
      assert f["W2-17"].winner_to == {"R64-17", :a}
      assert f["L2-1"].winner_to == {"R64-17", :b}
      assert f["W2-16"].winner_to == {"R64-16", :a}
      assert f["L2-32"].winner_to == {"R64-16", :b}
    end

    test "knockout rounds merge in pairs down to the final" do
      f = by_code(men())

      assert f["R64-1"].winner_to == {"R32-1", :a}
      assert f["R64-2"].winner_to == {"R32-1", :b}
      assert f["QF-1"].winner_to == {"SF-1", :a}
      assert f["SF-2"].winner_to == {"F-1", :b}
      assert f["F-1"].winner_to == nil
    end

    test "losing twice ends the run — no onward route from either losers' round" do
      f = by_code(men())

      assert f["L1-5"].loser_to == nil
      assert f["L2-5"].loser_to == nil
      assert f["R64-5"].loser_to == nil
      assert f["F-1"].loser_to == nil
    end

    test "every routed destination exists and every slot is filled exactly once" do
      bracket = men()
      codes = MapSet.new(bracket.fixtures, & &1.code)

      routes =
        Enum.flat_map(bracket.fixtures, fn fx ->
          Enum.filter([fx.winner_to, fx.loser_to], & &1)
        end)

      for {code, _side} <- routes do
        assert code in codes, "route points at missing fixture #{code}"
      end

      # Every slot other than the Winners R1 entry points is filled by exactly
      # one incoming route — no orphan slots, no two players routed into one.
      filled = Enum.frequencies(routes)
      needs_filling = Enum.reject(bracket.fixtures, &(&1.round_code == "W1"))

      for fx <- needs_filling, side <- [:a, :b] do
        assert Map.get(filled, {fx.code, side}) == 1,
               "#{fx.code} side #{side} has #{inspect(Map.get(filled, {fx.code, side}))} sources"
      end
    end

    test "nobody meets a player they already knocked out in the first knockout round" do
      bracket = men()
      f = by_code(bracket)

      # Which Winners R1 matches could each side of a knockout match have come
      # from? If those sets overlap, the draw has produced an immediate rematch.
      w1_sources =
        for fx <- bracket.fixtures, fx.round_code == "W1", reduce: %{} do
          acc ->
            acc
            |> put_source(fx.winner_to, fx.slot)
            |> put_source(fx.loser_to, fx.slot)
        end

      w2_l1_sources =
        for fx <- bracket.fixtures, fx.round_code in ["W2", "L1"], reduce: %{} do
          acc ->
            from = Map.fetch!(w1_sources, fx.code)

            acc
            |> merge_source(fx.winner_to, from)
            |> merge_source(fx.loser_to, from)
        end

      for fx <- bracket.fixtures, fx.round_code == "L2", reduce: :ok do
        _ ->
          from = Map.fetch!(w2_l1_sources, fx.code)
          merge_source(%{}, fx.winner_to, from)
          :ok
      end

      l2_sources =
        for fx <- bracket.fixtures, fx.round_code == "L2", reduce: %{} do
          acc -> merge_source(acc, fx.winner_to, Map.fetch!(w2_l1_sources, fx.code))
        end

      for j <- 1..32 do
        a_from = Map.fetch!(w2_l1_sources, "R64-#{j}") |> Map.get(:a, MapSet.new())
        b_from = Map.fetch!(l2_sources, "R64-#{j}") |> Map.get(:b, MapSet.new())

        assert MapSet.disjoint?(a_from, b_from),
               "R64-#{j} is a rematch: both sides came from Winners R1 match(es) " <>
                 "#{inspect(MapSet.intersection(a_from, b_from) |> MapSet.to_list())}"

        assert f["R64-#{j}"].slot == j
      end
    end
  end

  describe "byes" do
    test "a full field has none" do
      bracket = men()
      assert bracket.byes == 0
      assert Enum.all?(bracket.fixtures, &(&1.bye == false))
    end

    test "55 ladies in a 64 bracket leaves 9 byes" do
      bracket = DE.build(Enum.to_list(1..55), category: "female", byes: :random, rng: 1234)

      assert bracket.bracket_size == 64
      assert bracket.byes == 9
      assert Enum.count(bracket.fixtures, & &1.bye) == 9
    end

    test "every entrant is placed exactly once, byes included" do
      entrants = Enum.map(1..55, &"p#{&1}")
      bracket = DE.build(entrants, category: "female", byes: :random, rng: 7)

      placed =
        bracket.fixtures
        |> Enum.filter(&(&1.round_code == "W1"))
        |> Enum.flat_map(&[&1.a, &1.b])
        |> Enum.reject(&(&1 == :bye))

      assert Enum.sort(placed) == Enum.sort(entrants)
      assert length(placed) == 55
    end

    test "a bye routes its winner on but sends nobody to the losers' bracket" do
      bracket = DE.build(Enum.to_list(1..55), category: "female", byes: :random, rng: 99)
      byes = Enum.filter(bracket.fixtures, & &1.bye)

      for fx <- byes do
        assert fx.winner_to != nil
        assert fx.loser_to == nil, "#{fx.code} is a bye but still routes a loser"
      end
    end

    test "two byes never feed the same losers' match, over many random draws" do
      # The structural constraint from the format document: if both feeders of
      # one losers' match are byes it has no players at all and the crossover
      # comes up a player short.
      for seed <- 1..200 do
        bracket = DE.build(Enum.to_list(1..55), category: "female", byes: :random, rng: seed)

        bye_slots =
          bracket.fixtures
          |> Enum.filter(& &1.bye)
          |> Enum.map(& &1.slot)

        feeders = Enum.map(bye_slots, &div(&1 + 1, 2))

        assert length(Enum.uniq(feeders)) == length(feeders),
               "seed #{seed}: two byes feed losers' match #{inspect(feeders -- Enum.uniq(feeders))}"
      end
    end

    test "seeded byes also satisfy the constraint, and fall on the top seeds" do
      bracket = DE.build(Enum.to_list(1..55), category: "female", byes: :seeded)
      byes = Enum.filter(bracket.fixtures, & &1.bye)

      assert length(byes) == 9

      feeders = Enum.map(byes, &div(&1.slot + 1, 2))
      assert length(Enum.uniq(feeders)) == 9

      # The player sitting out is the stronger seed in each bye match.
      assert Enum.map(byes, & &1.a) |> Enum.sort() == Enum.to_list(1..9)
    end

    test "refuses a draw with more byes than losers' matches can absorb" do
      assert_raise ArgumentError, ~r/cannot be placed/, fn ->
        DE.build(Enum.to_list(1..20), byes: :random)
      end
    end

    test "refuses a field too small for a Circuit bracket" do
      assert_raise ArgumentError, ~r/at least 5 entrants/, fn ->
        DE.build([1, 2, 3])
      end
    end
  end

  defp put_source(acc, nil, _slot), do: acc

  defp put_source(acc, {code, side}, slot) do
    Map.update(acc, code, %{side => MapSet.new([slot])}, fn sides ->
      Map.update(sides, side, MapSet.new([slot]), &MapSet.put(&1, slot))
    end)
  end

  defp merge_source(acc, nil, _from), do: acc

  defp merge_source(acc, {code, side}, from) do
    slots = from |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    Map.update(acc, code, %{side => slots}, fn sides ->
      Map.update(sides, side, slots, &MapSet.union(&1, slots))
    end)
  end
end
