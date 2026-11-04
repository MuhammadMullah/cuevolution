defmodule Cuevolution.Competitions.DoubleEliminationTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.DoubleElimination, as: DE

  defp men, do: DE.build(Enum.to_list(1..128))
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
    test "a 128 men's field is the brief's bracket exactly" do
      %{rounds: rounds, depth: depth, qualifiers: qualifiers, fixtures: fixtures} =
        DE.build(Enum.to_list(1..128), category: "male")

      assert depth == 3
      assert qualifiers == 32

      counts = Map.new(rounds, &{&1.code, &1.matches})

      # Double elimination to the last 32: WB R1-R3 and LB R1-R4.
      assert counts == %{
               "W1" => 64,
               "W2" => 32,
               "W3" => 16,
               "L1" => 32,
               "L2" => 32,
               "L3" => 16,
               "L4" => 16,
               "R32" => 16,
               "R16" => 8,
               "QF" => 4,
               "SF" => 2,
               "F" => 1
             }

      assert length(fixtures) == 239
    end

    test "the losers' rounds eliminate exactly the brief's position bands" do
      %{rounds: rounds} = DE.build(Enum.to_list(1..128), category: "male")
      counts = Map.new(rounds, &{&1.code, &1.matches})

      # Everyone beaten in a losers' round is out, so its match count is the
      # size of that position band: 97-128, 65-96, 49-64, 33-48.
      assert counts["L1"] == 32
      assert counts["L2"] == 32
      assert counts["L3"] == 16
      assert counts["L4"] == 16

      # 96 out in the double elimination, 32 through to the single.
      assert counts["L1"] + counts["L2"] + counts["L3"] + counts["L4"] == 96
    end

    test "the men race to 6, except the losers' side at 5 and the final at 7" do
      %{rounds: rounds} = DE.build(Enum.to_list(1..128), category: "male")
      races = Map.new(rounds, &{&1.code, &1.race_to})

      # Round of 128 down to the semifinals, on the winners' side and in the
      # single elimination that follows it.
      for code <- ~w(W1 W2 W3 R32 R16 QF SF), do: assert(races[code] == 6)

      # Both exceptions: every losers' round is shorter, the final longer.
      for code <- ~w(L1 L2 L3 L4), do: assert(races[code] == 5)
      assert races["F"] == 7
    end

    test "the ladies' bracket is unchanged, pending the format decision" do
      %{rounds: rounds, depth: depth} = DE.build(Enum.to_list(1..64), category: "female")

      assert depth == 2
      counts = Map.new(rounds, &{&1.code, &1.matches})

      assert counts["W1"] == 32
      assert counts["W2"] == 16
      assert counts["L1"] == 16
      assert counts["L2"] == 16
      assert counts["R32"] == 16

      races = Map.new(rounds, &{&1.code, &1.race_to})
      assert races["W1"] == 4
      assert races["L1"] == 3
      assert races["F"] == 5
    end

    test "a small field runs the deepest double elimination it has room for" do
      # A demo draw cannot play three winners' rounds and still have a final,
      # so it drops to two rather than refusing.
      assert DE.build(Enum.to_list(1..8), category: "male").depth == 2
      assert DE.build(Enum.to_list(1..16), category: "male").depth == 3
      assert DE.build(Enum.to_list(1..128), category: "male").depth == 3
    end

    test "races can be overridden per draw without editing the module" do
      %{rounds: rounds} =
        DE.build(Enum.to_list(1..16), category: "male", races: %{winners: 9})

      assert rounds |> Enum.filter(&(&1.code == "W1")) |> hd() |> Map.fetch!(:race_to) == 9
    end
  end

  describe "routing" do
    setup do
      %{plan: DE.build(Enum.to_list(1..128), category: "male")}
    end

    test "Winners R1 sends winners up and losers across in matching slots", %{plan: plan} do
      first = find(plan, "W1-1")
      second = find(plan, "W1-2")

      assert first.winner_to == {"W2-1", :a}
      assert first.loser_to == {"L1-1", :a}
      assert second.winner_to == {"W2-1", :b}
      assert second.loser_to == {"L1-1", :b}
    end

    test "every crossover is mirrored, winners'-side dropper in slot A", %{plan: plan} do
      # W2 droppers enter L2 from the far end; W3 droppers enter L4 the same way.
      assert find(plan, "W2-1").loser_to == {"L2-32", :a}
      assert find(plan, "W2-32").loser_to == {"L2-1", :a}
      assert find(plan, "W3-1").loser_to == {"L4-16", :a}
      assert find(plan, "W3-16").loser_to == {"L4-1", :a}

      # And the losers'-side survivors take slot B at the same index.
      assert find(plan, "L1-1").winner_to == {"L2-1", :b}
      assert find(plan, "L3-1").winner_to == {"L4-1", :b}
    end

    test "odd losers' rounds pair up, even ones feed the next pairing", %{plan: plan} do
      # L2 winners pair into L3 two-to-one.
      assert find(plan, "L2-1").winner_to == {"L3-1", :a}
      assert find(plan, "L2-2").winner_to == {"L3-1", :b}
    end

    test "the last 32 is offset by half a round", %{plan: plan} do
      # W3 winners take slot A straight across; L4 winners are rotated into
      # slot B so nobody replays the match that put them there.
      assert find(plan, "W3-1").winner_to == {"R32-1", :a}
      assert find(plan, "L4-1").winner_to == {"R32-9", :b}
      assert find(plan, "L4-9").winner_to == {"R32-1", :b}
    end

    test "single-elimination rounds merge in pairs down to the final", %{plan: plan} do
      assert find(plan, "R32-1").winner_to == {"R16-1", :a}
      assert find(plan, "R32-2").winner_to == {"R16-1", :b}
      assert find(plan, "QF-1").winner_to == {"SF-1", :a}
      assert find(plan, "SF-2").winner_to == {"F-1", :b}
      assert find(plan, "F-1").winner_to == nil
    end

    test "a losers'-round defeat ends the run", %{plan: plan} do
      for code <- ~w(L1 L2 L3 L4), fixture <- round_fixtures(plan, code) do
        assert fixture.loser_to == nil,
               "#{fixture.code} should eliminate its loser"
      end
    end

    test "every routed destination exists and every slot is filled exactly once",
         %{plan: plan} do
      by_code = Map.new(plan.fixtures, &{&1.code, &1})

      writes =
        for f <- plan.fixtures,
            {code, side} <- Enum.reject([f.winner_to, f.loser_to], &is_nil/1) do
          assert Map.has_key?(by_code, code), "#{f.code} routes to a #{code} that does not exist"
          {code, side}
        end

      assert writes == Enum.uniq(writes), "a slot is written by two different matches"

      for f <- plan.fixtures, f.round_code != "W1" do
        assert Enum.count(writes, fn {code, _side} -> code == f.code end) == 2,
               "#{f.code} is not fed by exactly two matches"
      end
    end

    test "nobody meets a player they already knocked out, in the last 32", %{plan: plan} do
      {slots, met} = play_through(plan, stop_before: "R32")

      for f <- round_fixtures(plan, "R32") do
        a = Map.fetch!(slots, {f.code, :a})
        b = Map.fetch!(slots, {f.code, :b})

        refute MapSet.member?(met, MapSet.new([a, b])),
               "#{f.code} is a rematch between #{a} and #{b}"
      end
    end
  end

  # Plays the whole bracket with the lower seed number always winning,
  # returning where everyone ended up and every pairing that happened.
  defp play_through(plan, stop_before: stop) do
    Enum.reduce(plan.rounds, {%{}, MapSet.new()}, fn round, acc ->
      plan
      |> round_fixtures(round.code)
      |> Enum.reduce(acc, &play_fixture(&1, &2, round.code == stop))
    end)
  end

  defp play_fixture(fixture, {slots, met}, stop?) do
    a = Map.get(slots, {fixture.code, :a}, fixture[:a])
    b = Map.get(slots, {fixture.code, :b}, fixture[:b])
    met = if stop?, do: met, else: MapSet.put(met, MapSet.new([a, b]))
    {win, lose} = if a <= b, do: {a, b}, else: {b, a}

    {place(slots, [{fixture.winner_to, win}, {fixture.loser_to, lose}]), met}
  end

  defp place(slots, moves) do
    moves
    |> Enum.reject(fn {target, _player} -> is_nil(target) end)
    |> Enum.reduce(slots, fn {{code, side}, player}, acc ->
      Map.put(acc, {code, side}, player)
    end)
  end

  defp round_fixtures(plan, code), do: Enum.filter(plan.fixtures, &(&1.round_code == code))

  defp find(plan, code), do: Enum.find(plan.fixtures, &(&1.code == code))

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
end
