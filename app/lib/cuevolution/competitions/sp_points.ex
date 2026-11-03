defmodule Cuevolution.Competitions.SpPoints do
  @moduledoc """
  SP Points — the National Circuit ranking system (spec 014).

  Points are **derived**, never typed in. A player's total for one circuit is:

      2  for showing up
    + 3  for every match won (a bye counts as a win)
    + 20 champion / 10 runner-up / 5 semi-finalist
    + 5  at season end for playing all three circuits

  That is the whole rule set, and it is authoritative. The "totals by finish"
  table on the published format sheet was costed for a straight 128-player
  knockout — 7 winning matches to the title — and is three points low in every
  tier as a result: the actual format takes **8** wins to win it (two in the
  double-elimination phase, six in the knockout), by either route to the final.
  `totals_by_finish/1` re-derives that table from the rules so the corrected
  figures can be published.

  Deriving rather than storing means the ranking cannot drift from the
  results: correct a match and every affected total moves with it.
  """

  @show_up 2
  @per_win 3
  @bonuses %{champion: 20, runner_up: 10, semi_finalist: 5}
  @all_circuits_bonus 5
  @circuits_in_season 3

  @doc """
  Points earned at one circuit. `finish` is `:champion`, `:runner_up`,
  `:semi_finalist` or `:none` — the tiers that carry a bonus; a
  quarter-finalist scores on wins alone.

  A player who entered but lost their opening match still scores the 2 for
  showing up, which is what the sheet's "first round: 2" describes.
  """
  def circuit_points(wins, finish \\ :none) when is_integer(wins) and wins >= 0 do
    @show_up + @per_win * wins + Map.get(@bonuses, finish, 0)
  end

  @doc """
  Points earned by a team in the Circuit group stage: the same showing-up and
  per-win rates as the singles events.

  There is no finishing bonus here. The bonuses reward a champion, a runner-up
  and a semi-finalist, and a round robin produces none of those — the group
  stage decides who reaches the Nationals, and it is at the Nationals that a
  team can be champion. A team that tops its group on 9 wins scores
  `2 + 27 = 29`; one that loses all nine still scores the 2 for turning up.
  """
  def group_points(wins) when is_integer(wins) and wins >= 0, do: circuit_points(wins, :none)

  @doc "The end-of-season bonus: 5 points for playing all three circuits."
  def season_bonus(circuits_played) when is_integer(circuits_played) do
    if circuits_played >= @circuits_in_season, do: @all_circuits_bonus, else: 0
  end

  @doc """
  A player's season total: their per-circuit points plus the attendance bonus.
  `per_circuit` is the list of points they scored at each circuit they entered.
  """
  def season_total(per_circuit) when is_list(per_circuit) do
    Enum.sum(per_circuit) + season_bonus(length(per_circuit))
  end

  @doc """
  The corrected "totals by finish" table for a `category`, derived from the
  rules against the real format rather than a straight knockout.

  Returns `[{label, wins, points}]`, hardest finish first.
  """
  def totals_by_finish(category) do
    knockout_rounds = if category == "female", do: 5, else: 6

    # Everyone who reaches the knockout has already won two matches, whichever
    # side they came through: W1 + W2, or L1 + L2.
    into_knockout = 2

    knockout = [
      {"Champion", knockout_rounds, :champion},
      {"Runner-up", knockout_rounds - 1, :runner_up},
      {"Semi-finalist", knockout_rounds - 2, :semi_finalist},
      {"Quarter-finalist", knockout_rounds - 3, :none}
    ]

    # A player with n knockout wins goes out in the round of 2^(rounds - n):
    # two wins in a six-round knockout means losing in the last 16.
    early =
      for n <- (knockout_rounds - 4)..0//-1,
          do: {"Last #{Integer.pow(2, knockout_rounds - n)}", n, :none}

    double_elim = [
      {"Out in Losers Round 2", -1, :none},
      {"Out in Losers Round 1", -2, :none}
    ]

    for {label, knockout_wins, finish} <- knockout ++ early ++ double_elim do
      wins = max(into_knockout + knockout_wins, 0)
      {label, wins, circuit_points(wins, finish)}
    end
  end
end
