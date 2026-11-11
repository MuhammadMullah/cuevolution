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

  describe "rank/3 — points-first cascade" do
    test "ranks by points before wins and frame differential" do
      matches = [
        match(:a, :a, :b, 3, 2),
        match(:c, :c, :a, 3, 2),
        match(:b, :b, :c, 3, 2)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c], matches, cascade: :points_first)

      assert Enum.map(standings, & &1.participant_id) == [:a, :b, :c]
      assert Enum.map(standings, & &1.points) == [5, 5, 5]
      assert Enum.all?(standings, &(&1.tied == true))
    end

    test "does not award the clean-sweep bonus to a walkover" do
      standings =
        StandingsCalculator.rank(
          [:present, :absent],
          [
            match(:present, :present, :absent, 5, 0)
            |> Map.put(:status, "walkover")
            |> Map.put(:points_a, 3)
          ],
          cascade: :points_first
        )

      present = entry(standings, :present)
      assert present.points == 3
      assert present.bonus == 0
    end

    test "a drawn match (nil winner_id) counts points for both sides and a win for neither" do
      # Regional's 4-frame format allows a 2-2 draw — `match/5`'s winner
      # atom becomes `nil` here, same shape `to_calculator_match/1` produces
      # for a real tie.
      standings =
        StandingsCalculator.rank(
          [:a, :b],
          [
            match(nil, :a, :b, 2, 2)
            |> Map.put(:points_a, 2)
            |> Map.put(:points_b, 2)
          ],
          cascade: :points_first
        )

      a = entry(standings, :a)
      b = entry(standings, :b)

      assert a.wins == 0 and a.losses == 0
      assert b.wins == 0 and b.losses == 0
      assert a.points == 2 and b.points == 2
    end

    test "awards the Regional 4-0 clean-sweep bonus" do
      standings =
        StandingsCalculator.rank(
          [:a, :b],
          [match(:a, :a, :b, 4, 0)],
          cascade: :points_first
        )

      a = entry(standings, :a)
      assert a.points == 5
      assert a.bonus == 1
    end

    test "does not award the Regional 4-0 clean-sweep bonus to a walkover" do
      standings =
        StandingsCalculator.rank(
          [:present, :absent],
          [
            match(:present, :present, :absent, 4, 0)
            |> Map.put(:status, "walkover")
            |> Map.put(:points_a, 3)
          ],
          cascade: :points_first
        )

      present = entry(standings, :present)
      assert present.points == 3
      assert present.bonus == 0
    end
  end

  describe "rank/2 — a drawn match under the default :wins_first cascade" do
    test "counts points for neither side and a win for neither" do
      standings = StandingsCalculator.rank([:a, :b], [match(nil, :a, :b, 2, 2)])

      a = entry(standings, :a)
      b = entry(standings, :b)

      assert a.wins == 0 and a.losses == 0
      assert b.wins == 0 and b.losses == 0
    end
  end

  describe "rank/2 — the match and frame record every table prints" do
    test "matches and frames each split into played, won and lost" do
      matches = [
        match(:a, :a, :b, 3, 1),
        match(:a, :a, :c, 3, 0),
        match(:b, :b, :c, 3, 2)
      ]

      standings = StandingsCalculator.rank([:a, :b, :c], matches)
      a = entry(standings, :a)

      assert a.matches_played == 2
      assert a.wins == 2
      assert a.losses == 0
      assert a.win_pct == 100.0

      assert a.frames_played == 7
      assert a.frames_won == 6
      assert a.frames_lost == 1
      assert_in_delta a.frame_win_pct, 6 / 7 * 100, 0.001

      c = entry(standings, :c)

      assert c.matches_played == 2
      assert c.wins == 0
      assert c.losses == 2
      assert c.win_pct == 0.0
      # 0-3 then 2-3: eight frames played, two of them won.
      assert c.frames_played == 8
      assert c.frames_won == 2
      assert c.frames_lost == 6
      assert_in_delta c.frame_win_pct, 25.0, 0.001
    end

    test "every row's totals agree with its own parts" do
      matches = [
        match(:a, :a, :b, 3, 1),
        match(nil, :a, :c, 2, 2),
        match(:b, :b, :c, 3, 1)
      ]

      for row <- StandingsCalculator.rank([:a, :b, :c, :d], matches) do
        assert row.matches_played == row.wins + row.losses + row.draws
        assert row.frames_played == row.frames_won + row.frames_lost
        assert row.frame_diff == row.frames_won - row.frames_lost
      end
    end

    test "a drawn match counts as played and not won" do
      standings = StandingsCalculator.rank([:a, :b], [match(nil, :a, :b, 2, 2)])
      a = entry(standings, :a)

      assert a.draws == 1
      assert a.matches_played == 1
      assert a.win_pct == 0.0
      assert a.frames_played == 4
      assert a.frame_win_pct == 50.0
    end

    test "a participant with no matches has nil percentages rather than zero" do
      standings = StandingsCalculator.rank([:a, :b, :bye], [match(:a, :a, :b, 3, 1)])
      bye = entry(standings, :bye)

      assert bye.matches_played == 0
      assert bye.frames_played == 0
      assert is_nil(bye.win_pct)
      assert is_nil(bye.frame_win_pct)
    end
  end
end
