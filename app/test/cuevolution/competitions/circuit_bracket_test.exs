defmodule Cuevolution.Competitions.CircuitBracketTest do
  @moduledoc false
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp entrants(n, category) do
    for _ <- 1..n do
      insert(:stage_participation, stage_id: circuit().id, category: category)
    end
  end

  defp fixtures_for(bracket_id) do
    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket_id,
        preload: [round: r]
    )
  end

  describe "generate_circuit_bracket/4" do
    @tag :slow
    test "writes the whole men's bracket — rounds, fixtures and routing" do
      stage = circuit()
      players = entrants(16, "male")

      # W1, W2, L1, L2, then QF-SF-F: the agreed two-winners'-round shape.
      assert {:ok, %{bracket: bracket, rounds: 7, fixtures: 27}} =
               Competitions.generate_circuit_bracket(stage.id, "male", players)

      rounds = Repo.all(from r in Round, where: r.knockout_bracket_id == ^bracket.id)

      assert Enum.map(rounds, & &1.sequence) |> Enum.sort() == Enum.to_list(1..7)

      assert Enum.map(rounds, & &1.bracket_side) |> Enum.uniq() |> Enum.sort() ==
               ["knockout", "losers", "winners"]

      # Official men's race lengths survive the round trip.
      by_name = Map.new(rounds, &{&1.name, &1})
      assert by_name["Winners Round 1"].race_to == 6
      # The two exceptions to the race to 6: the losers' side is shorter and
      # the final is longer.
      assert by_name["Losers Round 1"].race_to == 5
      assert by_name["Final"].race_to == 7
    end

    test "fills Winners Round 1 from the draw and leaves the rest open" do
      stage = circuit()
      players = entrants(16, "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players)

      fixtures = fixtures_for(bracket.id)
      {w1, rest} = Enum.split_with(fixtures, &(&1.round.name == "Winners Round 1"))

      assert length(w1) == 8
      assert Enum.all?(w1, &(&1.participant_a_id && &1.participant_b_id))

      # Everyone drawn appears exactly once in Round 1.
      drawn = Enum.flat_map(w1, &[&1.participant_a_id, &1.participant_b_id])
      assert Enum.sort(drawn) == players |> Enum.map(& &1.id) |> Enum.sort()

      # Nothing downstream has players yet — they arrive via routing.
      assert Enum.all?(rest, &(is_nil(&1.participant_a_id) and is_nil(&1.participant_b_id)))
    end

    test "routing edges are persisted and point at real fixtures in this bracket" do
      stage = circuit()

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", entrants(16, "male"))

      fixtures = fixtures_for(bracket.id)
      ids = MapSet.new(fixtures, & &1.id)
      by_match = Map.new(fixtures, &{&1.match_id, &1})

      w1_1 = by_match["SP26-NAT-MS-W1-1"]
      assert w1_1.winner_to_side == "a"
      assert w1_1.loser_to_side == "a"
      assert by_match["SP26-NAT-MS-W2-1"].id == w1_1.winner_to_fixture_id
      assert by_match["SP26-NAT-MS-L1-1"].id == w1_1.loser_to_fixture_id

      # The crossover is mirrored and the knockout offset by half a round.
      assert by_match["SP26-NAT-MS-W2-4"].loser_to_fixture_id == by_match["SP26-NAT-MS-L2-1"].id
      # Two winners' rounds: W2 and L2 both feed the single elimination, the
      # losers' side rotated by half a round.
      assert by_match["SP26-NAT-MS-W2-1"].winner_to_fixture_id == by_match["SP26-NAT-MS-QF-1"].id
      assert by_match["SP26-NAT-MS-L2-1"].winner_to_fixture_id == by_match["SP26-NAT-MS-QF-3"].id
      assert by_match["SP26-NAT-MS-L2-1"].winner_to_side == "b"
      refute Map.has_key?(by_match, "SP26-NAT-MS-W3-1")

      # Losing on the losers' side ends the run.
      assert by_match["SP26-NAT-MS-L1-1"].loser_to_fixture_id == nil
      assert by_match["SP26-NAT-MS-L1-1"].loser_to_side == nil

      for f <- fixtures, id <- [f.winner_to_fixture_id, f.loser_to_fixture_id], id != nil do
        assert id in ids
      end
    end

    test "the ladies' bracket uses the ladies' race lengths" do
      stage = circuit()

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "female", entrants(16, "female"))

      rounds =
        Repo.all(from r in Round, where: r.knockout_bracket_id == ^bracket.id)
        |> Map.new(&{&1.name, &1})

      assert rounds["Winners Round 1"].race_to == 4
      assert rounds["Losers Round 1"].race_to == 3
      assert rounds["Final"].race_to == 5
    end

    test "a bye is recorded as a walkover and routes nobody to the losers' side" do
      stage = circuit()

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "female", entrants(13, "female"),
          byes: :random,
          rng: 5
        )

      byes = bracket.id |> fixtures_for() |> Enum.filter(& &1.bye)

      assert length(byes) == 3

      for fx <- byes do
        assert fx.status == "walkover"
        assert fx.walkover_kind == "single"
        assert fx.loser_to_fixture_id == nil
        assert fx.winner_to_fixture_id != nil
      end
    end

    test "refuses to regenerate over an existing bracket" do
      stage = circuit()

      assert {:ok, _} =
               Competitions.generate_circuit_bracket(stage.id, "male", entrants(8, "male"))

      assert {:error, :bracket_exists} =
               Competitions.generate_circuit_bracket(stage.id, "male", entrants(8, "male"))
    end

    test "generation is all-or-nothing" do
      stage = circuit()

      assert_raise ArgumentError, fn ->
        Competitions.generate_circuit_bracket(stage.id, "male", entrants(3, "male"))
      end

      bracket = Competitions.get_knockout_bracket(stage.id, "male")
      assert bracket == nil or fixtures_for(bracket.id) == []
    end
  end
end
