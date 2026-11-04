defmodule Cuevolution.Competitions.SpPointsTest do
  @moduledoc """
  The SP Points rules from the Nov 2026 brief: stage-based through the
  double-elimination phase, per win from the last 32.
  """
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.SpPoints

  describe "circuit_points/1" do
    test "turning up and nothing else is 2" do
      assert SpPoints.circuit_points(%{}) == 2
      assert SpPoints.circuit_points(%{exit_round: "L1"}) == 2
    end

    test "a no-show scores nothing at all" do
      assert SpPoints.circuit_points(%{showed_up?: false}) == 0

      # Not even if the bracket says they went a long way.
      assert SpPoints.circuit_points(%{showed_up?: false, qualified?: true, se_wins: 5}) == 0
    end

    test "the double-elimination phase pays by stage, not by win" do
      # Two players out in LB R3 by different routes — one came through WB R1,
      # won LB R1 and LB R2; the other dropped from WB R2 and won only LB R2.
      # Different win counts, same stage, so the same points.
      assert SpPoints.circuit_points(%{exit_round: "L3"}) == 7
      assert SpPoints.circuit_points(%{exit_round: "L3", se_wins: 0}) == 7
    end

    test "each losers'-round exit is worth what the brief says" do
      assert SpPoints.circuit_points(%{exit_round: "L1"}) == 2
      assert SpPoints.circuit_points(%{exit_round: "L2"}) == 5
      assert SpPoints.circuit_points(%{exit_round: "L3"}) == 7
      assert SpPoints.circuit_points(%{exit_round: "L4"}) == 9
    end

    test "reaching the last 32 is 11, whichever side you came through" do
      assert SpPoints.circuit_points(%{qualified?: true, se_wins: 0}) == 11
    end

    test "from the last 32 each win adds 3" do
      assert SpPoints.circuit_points(%{qualified?: true, se_wins: 1}) == 14
      assert SpPoints.circuit_points(%{qualified?: true, se_wins: 2}) == 17
    end

    test "the finish bonus is added once and does not stack" do
      semi = SpPoints.circuit_points(%{qualified?: true, se_wins: 3, finish: :semi_finalist})
      runner = SpPoints.circuit_points(%{qualified?: true, se_wins: 4, finish: :runner_up})
      champ = SpPoints.circuit_points(%{qualified?: true, se_wins: 5, finish: :champion})

      assert semi == 25
      assert runner == 33
      assert champ == 46

      # The champion gets 20, not 20 + 10 + 5.
      assert champ == 2 + 9 + 3 * 5 + 20
    end

    test "wins in the double-elimination phase score nothing on their own" do
      # `se_wins` is ignored unless the player qualified.
      assert SpPoints.circuit_points(%{exit_round: "L2", se_wins: 4}) == 5
    end
  end

  describe "totals_by_finish/2" do
    test "it reproduces the men's published table exactly" do
      expected = [
        {"Champion", {1, 1}, 46},
        {"Runner-up", {2, 2}, 33},
        {"Semi-finalist", {3, 4}, 25},
        {"Quarter-finalist", {5, 8}, 17},
        {"Last 16", {9, 16}, 14},
        {"Last 32", {17, 32}, 11},
        {"Out in LB R4", {33, 48}, 9},
        {"Out in LB R3", {49, 64}, 7},
        {"Out in LB R2", {65, 96}, 5},
        {"Out in LB R1", {97, 128}, 2}
      ]

      assert SpPoints.totals_by_finish(128, 3) == expected
    end

    test "the position bands account for all 128 players exactly once" do
      bands = SpPoints.totals_by_finish(128, 3)

      covered = Enum.flat_map(bands, fn {_label, {from, to}, _pts} -> Enum.to_list(from..to) end)

      assert Enum.sort(covered) == Enum.to_list(1..128)
    end

    test "points never increase as the finish gets worse" do
      points = SpPoints.totals_by_finish(128, 3) |> Enum.map(fn {_l, _p, pts} -> pts end)

      assert points == Enum.sort(points, :desc)
    end
  end

  describe "configuration" do
    test "an award can be overridden without a code change" do
      Application.put_env(:cuevolution, :sp_points, %{per_win: 4})

      on_exit(fn -> Application.delete_env(:cuevolution, :sp_points) end)

      # 2 + 9 + 4*5 + 20
      assert SpPoints.circuit_points(%{qualified?: true, se_wins: 5, finish: :champion}) == 51
      # Everything not overridden keeps its default.
      assert SpPoints.circuit_points(%{exit_round: "L3"}) == 7
    end
  end

  describe "season totals" do
    test "the bonus lands only once all three circuits are played" do
      assert SpPoints.season_bonus(2) == 0
      assert SpPoints.season_bonus(3) == 5
      assert SpPoints.season_total([46, 33, 25]) == 109
      assert SpPoints.season_total([46, 33]) == 79
    end
  end

  describe "the team round robin keeps the per-win rule" do
    test "2 for entering plus 3 a win" do
      assert SpPoints.group_points(0) == 2
      assert SpPoints.group_points(9) == 29
    end
  end
end
