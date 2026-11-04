defmodule Cuevolution.Competitions.SpPoints do
  @moduledoc """
  SP Points — the National Circuit ranking system (SP Points & Standings brief,
  Nov 2026).

  **Points are fixed by the stage a player goes out at, not by the route they
  took.** That is the whole idea. The two sides of a double-elimination bracket
  need different numbers of wins to reach the same stage, so paying per win
  would rank a losers'-side survivor above a winners'-side one who got just as
  far. Everyone who reaches the last 32 has 11 points, whichever side they came
  through.

  Two regimes, either side of the last 32:

    * **Double-elimination phase** — points come from the stage reached. An
      individual win here scores nothing on its own.
    * **Last 32 onwards** — 3 points a win, where a bye or walkover counts as a
      win, plus one finish bonus at the end.

  Per circuit, for a 128 men's draw:

      Champion          1       46
      Runner-up         2       33
      Semi-finalist     3-4     25
      Quarter-finalist  5-8     17
      Last 16           9-16    14
      Last 32          17-32    11
      Out in LB R4     33-48     9
      Out in LB R3     49-64     7
      Out in LB R2     65-96     5
      Out in LB R1    97-128     2

  Every number above is derived by `totals_by_finish/1` from the rules rather
  than typed in, so the published table and the engine cannot disagree.

  The values are configurable without a code change, per the brief:

      config :cuevolution, :sp_points, %{per_win: 4}

  is merged over `defaults/0`.
  """

  @defaults %{
    # Awarded on check-in and playing (or receiving) a first match. A player
    # who does not turn up gets nothing.
    show_up: 2,
    # Single-elimination phase only.
    per_win: 3,
    # What reaching each stage of the double-elimination phase is worth, on top
    # of showing up. Keyed by the losers'-round code a player goes out in;
    # `:qualified` is reaching the single elimination.
    stage_awards: %{"L1" => 0, "L2" => 3, "L3" => 5, "L4" => 7, qualified: 9},
    # One bonus only, for the final finish — they do not stack.
    bonuses: %{champion: 20, runner_up: 10, semi_finalist: 5},
    all_circuits_bonus: 5,
    circuits_in_season: 3
  }

  @doc "The built-in values, before any application config is merged over them."
  def defaults, do: @defaults

  @doc """
  The live values: `defaults/0` with `config :cuevolution, :sp_points` merged
  over the top, one level deep so a single award can be overridden without
  restating the rest.
  """
  def config do
    Application.get_env(:cuevolution, :sp_points, %{})
    |> Enum.reduce(@defaults, fn
      {key, %{} = overrides}, acc when is_map_key(@defaults, key) ->
        Map.update!(acc, key, &Map.merge(&1, overrides))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  @doc """
  Points for one circuit, from a description of how a player's run went:

    * `:showed_up?` — false for a no-show, who scores nothing at all.
    * `:exit_round` — the round code they were knocked out in, or `nil` for the
      champion.
    * `:qualified?` — true once they reach the single elimination.
    * `:se_wins` — matches won from the last 32 onwards, byes and walkovers
      included.
    * `:finish` — `:champion`, `:runner_up`, `:semi_finalist` or `:none`.

  Anything omitted takes the quietest value, so `circuit_points(%{})` is the
  2 for turning up and nothing else.
  """
  def circuit_points(run \\ %{}) when is_map(run) do
    c = config()

    if Map.get(run, :showed_up?, true) do
      c.show_up + stage_award(c, run) + se_points(c, run) + bonus(c, run)
    else
      0
    end
  end

  # In the double-elimination phase the stage reached is the whole story.
  defp stage_award(c, run) do
    if Map.get(run, :qualified?, false) do
      Map.fetch!(c.stage_awards, :qualified)
    else
      Map.get(c.stage_awards, Map.get(run, :exit_round), 0)
    end
  end

  defp se_points(c, run) do
    if Map.get(run, :qualified?, false), do: c.per_win * Map.get(run, :se_wins, 0), else: 0
  end

  defp bonus(c, run), do: Map.get(c.bonuses, Map.get(run, :finish, :none), 0)

  @doc """
  Points earned by a team in the Circuit group stage.

  The team event is a round robin, not a bracket, so "the stage you went out
  at" has no meaning for it — every team plays all nine matches. It therefore
  keeps the per-win rule: 2 for entering plus 3 a win. The Nov 2026 brief
  covers singles only and does not change this.

  A team that wins all nine scores `2 + 27 = 29`; one that loses all nine still
  scores the 2 for turning up.
  """
  def group_points(wins) when is_integer(wins) and wins >= 0 do
    c = config()
    c.show_up + c.per_win * wins
  end

  @doc "The end-of-season bonus: 5 points for playing all three circuits."
  def season_bonus(circuits_played) when is_integer(circuits_played) do
    c = config()
    if circuits_played >= c.circuits_in_season, do: c.all_circuits_bonus, else: 0
  end

  @doc """
  A player's season total: their per-circuit points plus the attendance bonus.
  `per_circuit` is the list of points they scored at each circuit they entered.

  The bonus lands only once the third circuit is complete, so a two-circuit
  list gets nothing added.
  """
  def season_total(per_circuit) when is_list(per_circuit) do
    Enum.sum(per_circuit) + season_bonus(length(per_circuit))
  end

  @doc """
  The published "points by finish" table for a `bracket_size`, derived from the
  rules. Returns `[{label, positions, points}]`, best finish first.

  `positions` is the shared band — `{1, 1}` for the champion, `{3, 4}` for the
  semi-finalists, `{97, 128}` for everyone out in LB R1 — since players who go
  out at the same stage share a position.
  """
  def totals_by_finish(bracket_size \\ 128, depth \\ 3) do
    se = div(bracket_size, Integer.pow(2, depth - 1))

    single_elimination_bands(se) ++ losers_bands(bracket_size, depth, se)
  end

  # Walking back from the final: the champion, the runner-up, then each earlier
  # round's losers as a band twice the size of the one before.
  defp single_elimination_bands(se) do
    rounds = se |> Stream.iterate(&div(&1, 2)) |> Enum.take_while(&(&1 >= 2)) |> Enum.reverse()
    wins = length(rounds)

    champion = {"Champion", {1, 1}, circuit_points(qualified(wins, :champion))}
    runner_up = {"Runner-up", {2, 2}, circuit_points(qualified(wins - 1, :runner_up))}

    {rest, _from} =
      rounds
      |> Enum.drop(1)
      |> Enum.with_index()
      |> Enum.map_reduce(3, fn {players, index}, from ->
        losers = div(players, 2)
        finish = if index == 0, do: :semi_finalist, else: :none
        label = band_label(players)
        points = circuit_points(qualified(wins - 2 - index, finish))
        {{label, {from, from + losers - 1}, points}, from + losers}
      end)

    [champion, runner_up | rest]
  end

  defp band_label(4), do: "Semi-finalist"
  defp band_label(8), do: "Quarter-finalist"
  defp band_label(n), do: "Last #{n}"

  defp qualified(se_wins, finish),
    do: %{qualified?: true, se_wins: max(se_wins, 0), finish: finish}

  # Then the losers' rounds, last first: LB R4's losers are 33-48, LB R1's are
  # the bottom of the draw.
  defp losers_bands(bracket_size, depth, se) do
    last = 2 * depth - 2

    {bands, _from} =
      last..1//-1
      |> Enum.map_reduce(se + 1, fn j, from ->
        losers = div(bracket_size, Integer.pow(2, div(j + 1, 2) + 1))
        points = circuit_points(%{exit_round: "L#{j}"})
        {{"Out in LB R#{j}", {from, from + losers - 1}, points}, from + losers}
      end)

    bands
  end
end
