defmodule Cuevolution.Competitions.StandingsCalculatorTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.StandingsCalculator

  defp match(winner, a, b, frames_a, frames_b) do
    %{
      winner_id: winner,
      participant_a_id: a,
      participant_b_id: b,
      frames_won_a: frames_a,
      frames_won_b: frames_b
    }
  end

  defp entry(standings, id), do: Enum.find(standings, &(&1.participant_id == id))

  describe "rank/2 — level 1: clean win-count ordering" do
    test "ranks participants strictly by match wins, no ties" do
      matches = [
        match(:a, :a, :b, 3, 1),
        match(:a, :a, :c, 3, 0),
        match(:b, :b, :c, 3, 2)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c], matches)

      assert Enum.map(standings, & &1.participant_id) == [:a, :b, :c]
      assert Enum.map(standings, & &1.rank) == [1, 2, 3]
      assert Enum.all?(standings, &(&1.tied == false))
      assert entry(standings, :a).wins == 2
      assert entry(standings, :b).wins == 1
      assert entry(standings, :c).wins == 0
    end
  end

  describe "rank/2 — level 2: wins-tied resolved by head-to-head" do
    test "the participant who beat the other head-to-head ranks above them" do
      # A and B both finish 2-1; A beat B directly.
      matches = [
        match(:a, :a, :b, 3, 1),
        match(:c, :a, :c, 1, 3),
        match(:a, :a, :d, 3, 0),
        match(:b, :b, :c, 3, 1),
        match(:b, :b, :d, 3, 0),
        match(:d, :c, :d, 3, 2)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c, :d], matches)

      assert entry(standings, :a).wins == 2
      assert entry(standings, :b).wins == 2

      a_rank = entry(standings, :a).rank
      b_rank = entry(standings, :b).rank
      assert a_rank < b_rank
      refute entry(standings, :a).tied
      refute entry(standings, :b).tied
    end
  end

  describe "rank/2 — level 3: head-to-head-tied resolved by frame differential" do
    test "a 3-way win cycle (no head-to-head separation) falls through to frame differential" do
      # P1 beats P2, P2 beats P3, P3 beats P1 — each has exactly 1 win and
      # 1 head-to-head win within the tied trio, so head-to-head can't
      # separate them. Frame differential must.
      matches = [
        match(:p1, :p1, :p2, 3, 0),
        match(:p2, :p2, :p3, 3, 1),
        match(:p3, :p3, :p1, 2, 0)
      ]

      standings = StandingsCalculator.rank([:p1, :p2, :p3], matches)

      assert Enum.all?(standings, &(&1.wins == 1))

      assert entry(standings, :p1).frame_diff == 1
      assert entry(standings, :p3).frame_diff == 0
      assert entry(standings, :p2).frame_diff == -1

      assert Enum.map(standings, & &1.participant_id) == [:p1, :p3, :p2]
      assert Enum.all?(standings, &(&1.tied == false))
    end
  end

  describe "rank/2 — level 4: frame-differential-tied resolved by total frames won" do
    test "equal wins, no head-to-head, equal frame differential — more frames won ranks higher" do
      matches = [
        match(:a, :a, :c, 3, 1),
        match(:a, :a, :d, 2, 0),
        match(:b, :b, :d2, 4, 2),
        match(:b, :b, :e, 3, 1)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c, :d, :d2, :e], matches)

      a = entry(standings, :a)
      b = entry(standings, :b)

      assert a.wins == 2
      assert b.wins == 2
      assert a.frame_diff == 4
      assert b.frame_diff == 4
      assert a.frames_won == 5
      assert b.frames_won == 7

      assert b.rank < a.rank
      refute a.tied
      refute b.tied
    end
  end

  describe "rank/2 — level 5: fully tied after every level is flagged for admin resolution" do
    test "identical wins, no head-to-head, identical frame differential and frames won" do
      matches = [
        match(:a, :a, :c, 3, 1),
        match(:b, :b, :d, 3, 1)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c, :d], matches)

      a = entry(standings, :a)
      b = entry(standings, :b)

      assert a.wins == 1 and b.wins == 1
      assert a.frame_diff == 2 and b.frame_diff == 2
      assert a.frames_won == 3 and b.frames_won == 3

      assert a.tied
      assert b.tied
      assert a.rank == b.rank - 1 or b.rank == a.rank - 1
    end
  end

  describe "rank/2 — participants with zero matches (bye)" do
    test "a participant with no matches still appears in the standings with all-zero stats" do
      matches = [match(:a, :a, :b, 3, 0)]

      standings = StandingsCalculator.rank([:a, :b, :bye], matches)

      assert length(standings) == 3

      bye = entry(standings, :bye)
      assert bye.wins == 0
      assert bye.losses == 0
      assert bye.frame_diff == 0
      assert bye.frames_won == 0
    end
  end
end
