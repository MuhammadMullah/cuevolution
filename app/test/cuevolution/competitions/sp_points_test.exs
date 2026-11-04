defmodule Cuevolution.Competitions.SpPointsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.SpPoints, as: SP

  describe "circuit_points/2" do
    test "2 for showing up, 3 a win, plus the finishing bonus" do
      assert SP.circuit_points(0) == 2
      assert SP.circuit_points(1) == 5
      assert SP.circuit_points(4) == 14
      assert SP.circuit_points(6, :semi_finalist) == 25
      assert SP.circuit_points(7, :runner_up) == 33
      assert SP.circuit_points(8, :champion) == 46
    end

    test "a quarter-finalist scores on wins alone" do
      assert SP.circuit_points(5, :none) == SP.circuit_points(5)
      assert SP.circuit_points(5) == 17
    end

    test "entering and losing the opening match still scores the showing-up points" do
      assert SP.circuit_points(0) == 2
    end
  end

  describe "season_bonus/1 and season_total/1" do
    test "5 points only once all three circuits are played" do
      assert SP.season_bonus(1) == 0
      assert SP.season_bonus(2) == 0
      assert SP.season_bonus(3) == 5
    end

    test "a season total is the circuits plus the attendance bonus" do
      assert SP.season_total([46, 17, 8]) == 76
      assert SP.season_total([46, 17]) == 63
      assert SP.season_total([]) == 0
    end
  end

  describe "totals_by_finish/1" do
    test "men's corrected table — three higher than the published sheet" do
      table = Map.new(SP.totals_by_finish("male"), fn {label, _w, pts} -> {label, pts} end)

      # Published sheet had 43/30/22/14/11/8/5 — costed for a straight 128
      # knockout, which is one win short of this format.
      assert table["Champion"] == 46
      assert table["Runner-up"] == 33
      assert table["Semi-finalist"] == 25
      assert table["Quarter-finalist"] == 17
      assert table["Last 16"] == 14
      assert table["Last 32"] == 11
      assert table["Last 64"] == 8
    end

    test "ladies' corrected table" do
      table = Map.new(SP.totals_by_finish("female"), fn {label, _w, pts} -> {label, pts} end)

      assert table["Champion"] == 43
      assert table["Runner-up"] == 30
      assert table["Semi-finalist"] == 22
      assert table["Quarter-finalist"] == 14
      assert table["Last 16"] == 11
      assert table["Last 32"] == 8
      refute Map.has_key?(table, "Last 64")
    end

    test "the double-elimination exits the sheet omits are included" do
      table = Map.new(SP.totals_by_finish("male"), fn {label, _w, pts} -> {label, pts} end)

      # 32 men finish 65th-96th with exactly one win. The sheet has no row for
      # them, and 5 collides with its printed "Last 64".
      assert table["Out in Losers Round 2"] == 5
      assert table["Out in Losers Round 1"] == 2
    end

    test "a champion wins 8 matches for men and 7 for ladies" do
      assert {"Champion", 8, 46} = hd(SP.totals_by_finish("male"))
      assert {"Champion", 7, 43} = hd(SP.totals_by_finish("female"))
    end

    test "each tier is exactly one win apart" do
      wins = SP.totals_by_finish("male") |> Enum.map(fn {_l, w, _p} -> w end)
      assert wins == [8, 7, 6, 5, 4, 3, 2, 1, 0]
    end
  end
end
