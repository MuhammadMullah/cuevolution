defmodule Cuevolution.Competitions.DerbiesFirstTest do
  @moduledoc """
  `Competitions.derbies_first/1` on its own — the rule that a same-region
  meeting is played early rather than left until the group is decided.
  """
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions

  defp team(region), do: %{region_id: region}

  describe "ordering rounds" do
    test "a round holding a derby is brought in front of one that holds none" do
      clear = [{team("a"), team("b")}]
      derby = [{team("c"), team("c")}]

      assert Competitions.derbies_first([clear, derby]) == [derby, clear]
    end

    test "rounds are ordered by how many derbies they hold" do
      one = [{team("a"), team("a")}, {team("b"), team("c")}]
      two = [{team("d"), team("d")}, {team("e"), team("e")}]
      none = [{team("f"), team("g")}]

      assert Competitions.derbies_first([none, one, two]) == [two, one, none]
    end

    test "rounds level on derbies keep the order the draw produced" do
      first = [{team("a"), team("b")}]
      second = [{team("c"), team("d")}]
      third = [{team("e"), team("f")}]

      assert Competitions.derbies_first([first, second, third]) == [first, second, third]
    end

    test "a group whose teams all share a region comes out unchanged" do
      # Every Regional group looks like this, and reordering it would be noise.
      rounds =
        for n <- 1..4 do
          [{team("same"), team("same")}, {%{region_id: "same", n: n}, team("same")}]
        end

      assert Competitions.derbies_first(rounds) == rounds
    end

    test "no round is lost, duplicated or emptied" do
      rounds = [
        [{team("a"), team("b")}, {team("c"), team("d")}],
        [{team("e"), team("e")}, {team("f"), team("g")}],
        [{team("h"), team("i")}, {team("j"), team("j")}]
      ]

      reordered = Competitions.derbies_first(rounds)

      assert length(reordered) == length(rounds)
      assert Enum.map(reordered, &length/1) == [2, 2, 2]

      pairs = fn list -> list |> List.flatten() |> Enum.map(&MapSet.new(Tuple.to_list(&1))) end
      assert Enum.sort(pairs.(reordered)) == Enum.sort(pairs.(rounds))
    end
  end

  describe "ordering within a round" do
    test "the derby takes the earlier match number" do
      round = [{team("a"), team("b")}, {team("c"), team("c")}, {team("d"), team("e")}]

      assert [{%{region_id: "c"}, %{region_id: "c"}} | rest] =
               Competitions.derbies_first([round]) |> hd()

      assert length(rest) == 2
    end
  end

  describe "teams with no region" do
    test "two of them are not a derby" do
      # Unknown is not a place, so a missing region must not pair people up.
      rounds = [[{team("a"), team("b")}], [{team(nil), team(nil)}]]

      assert Competitions.derbies_first(rounds) == rounds
    end
  end

  test "an empty round robin is left alone" do
    assert Competitions.derbies_first([]) == []
  end
end
