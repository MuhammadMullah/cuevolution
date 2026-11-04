defmodule Cuevolution.Competitions.DoubleElimination do
  @moduledoc """
  Builds the Circuit stage bracket as plain data — no `Repo`, no side effects.

  The Circuit format is a *truncated* double elimination followed by a straight
  knockout (see `project-scope/specs/014-circuit-stage-format/`):

    * **Winners Round 1** — the whole field. Winners stay unbeaten, losers drop.
    * **Winners Round 2** — the unbeaten half. Winners qualify, losers drop.
    * **Losers Round 1** — the WR1 losers. Losing here is a second loss: out.
    * **Losers Round 2 (crossover)** — LR1 winners meet the WR2 droppers.
    * **Knockout** — the unbeaten half plus the one-loss survivors, single
      elimination down to a champion.

  A 128 field produces 64 qualifiers and 223 matches; a 64 field produces 32
  qualifiers and 93. Those totals, the seeding, and all three pairing rules
  below are taken from the 2026 sample draw rather than invented here:

    * **Seeding** is the standard recursive bracket order — 1 v 128, 64 v 65,
      32 v 97, 33 v 96 … (`seed_order/1`).
    * **The crossover is mirrored**: `L2-k` pairs the loser of `W2-(n+1-k)`
      against the `L1-k` winner, the winners'-side player in slot A.
    * **The knockout is offset by half a round**: `K-j` pairs the `W2-j` winner
      against the `L2-m` winner where `m` is `j` rotated by half the round.
      Pairing `W2-j` with `L2-j` instead would put a player straight back in
      against someone they already knocked out in WR1 — the offset exists to
      prevent that, and `double_elimination_test.exs` asserts it holds for
      every match in a 128 draw.

  `build/1` returns `%{rounds: [...], fixtures: [...]}` where each fixture
  carries where its winner goes and where its loser goes, as
  `{fixture_code, :a | :b}` or `nil` for "eliminated". Persisting that graph is
  `Competitions.generate_circuit_bracket/2`'s job, not this module's.
  """

  # Race lengths from the official SportPesa National Pool Circuit 2026/27
  # format sheet: "race to N all through", with the losers' side shorter and
  # the final longer. The sheet calls out only the final as an exception at
  # the business end, so the semifinal runs at the knockout length.
  @races %{
    "male" => %{winners: 6, losers: 5, knockout: 6, semifinal: 6, final: 7},
    "female" => %{winners: 4, losers: 3, knockout: 4, semifinal: 4, final: 5}
  }

  @doc ~S(The official race lengths for `category` — "male" or "female".)
  def races_for(category) when is_map_key(@races, category), do: Map.fetch!(@races, category)

  @doc """
  Builds the full bracket for `entrants` (a list of anything — participation
  ids, seeds, structs — in seeding order, best first).

  Options:

    * `:category` — `"male"` (default) or `"female"`, which selects the
      official race lengths for that event.
    * `:races` — a map merged over the category's defaults, for a one-off
      variation without editing the module.
    * `:byes` — `:seeded` (default) puts the byes on the strongest seeds, which
      is what a rated draw does. `:random` scatters them, which is what the
      ladies' draw calls for; pass `:rng` to make that reproducible.
    * `:rng` — a `:rand` state or an integer seed, used only by `:random`.

  Raises if `entrants` would need a bracket smaller than 8.
  """
  def build(entrants, opts \\ []) when is_list(entrants) do
    field = length(entrants)
    bracket = bracket_size(field)

    if bracket < 8 do
      raise ArgumentError, "a Circuit bracket needs at least 5 entrants, got #{field}"
    end

    races =
      opts
      |> Keyword.get(:category, "male")
      |> races_for()
      |> Map.merge(Map.new(Keyword.get(opts, :races, %{})))

    slots = assign_slots(entrants, bracket, opts)

    rounds = build_rounds(bracket, races)
    fixtures = build_fixtures(bracket, slots)

    %{rounds: rounds, fixtures: fixtures, bracket_size: bracket, byes: bracket - field}
  end

  @doc "The smallest power of two that holds `field`."
  def bracket_size(field) when field > 0 do
    1 |> Stream.iterate(&(&1 * 2)) |> Enum.find(&(&1 >= field))
  end

  @doc """
  Standard bracket seeding order for a power-of-two `size`: the seed numbers
  read top to bottom, so consecutive pairs are the Round 1 matches. Every pair
  sums to `size + 1`, which is what makes 1 v 128 and 64 v 65 fall out.
  """
  def seed_order(1), do: [1]

  def seed_order(size) do
    size |> div(2) |> seed_order() |> Enum.flat_map(&[&1, size + 1 - &1])
  end

  @doc "The Winners Round 1 seed pairings, in match order."
  def seed_pairs(size) do
    size |> seed_order() |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1)
  end

  # ---------------------------------------------------------------- the draw

  # Returns %{seed_number => entrant | :bye}.
  defp assign_slots(entrants, bracket, opts) do
    field = length(entrants)
    bye_count = bracket - field

    case {bye_count, Keyword.get(opts, :byes, :seeded)} do
      {0, _} ->
        entrants |> Enum.with_index(1) |> Map.new(fn {e, seed} -> {seed, e} end)

      {_, :seeded} ->
        # Byes take the weakest seed numbers, so their opponents — the top
        # seeds — are the ones who sit out. Standard seeding already spreads
        # those matches apart, so the losers'-bracket constraint below holds
        # without doing anything extra (asserted in the tests).
        entrants
        |> Enum.with_index(1)
        |> Map.new(fn {e, seed} -> {seed, e} end)
        |> then(fn m -> Enum.reduce((field + 1)..bracket, m, &Map.put(&2, &1, :bye)) end)

      {_, :random} ->
        random_slots(entrants, bracket, bye_count, Keyword.get(opts, :rng))
    end
  end

  # A bye leaves its Round 1 match with no loser, so the losers'-bracket match
  # fed by that pair is a slot short. If BOTH matches feeding one losers' match
  # are byes it has no players at all and the crossover comes up short — the
  # draw would be structurally broken, not merely lopsided. Choosing distinct
  # feeder pairs first and then one match inside each makes that impossible by
  # construction rather than by retrying until it validates.
  defp random_slots(entrants, bracket, bye_count, rng) do
    seed_rng(rng)
    w1_matches = div(bracket, 2)
    feeder_pairs = div(w1_matches, 2)

    if bye_count > feeder_pairs do
      raise ArgumentError,
            "#{bye_count} byes cannot be placed in a #{bracket} bracket without two " <>
              "of them feeding the same losers' match (max #{feeder_pairs})"
    end

    bye_matches =
      1..feeder_pairs
      |> Enum.take_random(bye_count)
      |> Enum.map(fn pair -> 2 * pair - Enum.random([0, 1]) end)

    pairs = seed_pairs(bracket)
    shuffled = Enum.shuffle(entrants)

    {slots, []} =
      pairs
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, shuffled}, fn {{high, low}, match}, {acc, pool} ->
        if match in bye_matches do
          [player | rest] = pool
          {acc |> Map.put(high, player) |> Map.put(low, :bye), rest}
        else
          [a, b | rest] = pool
          {acc |> Map.put(high, a) |> Map.put(low, b), rest}
        end
      end)

    slots
  end

  defp seed_rng(nil), do: :ok
  defp seed_rng(seed) when is_integer(seed), do: :rand.seed(:exsss, {seed, seed, seed})
  defp seed_rng(state), do: :rand.seed(state)

  # ------------------------------------------------------------------ rounds

  defp build_rounds(bracket, races) do
    w1 = div(bracket, 2)
    w2 = div(bracket, 4)

    [
      %{
        code: "W1",
        name: "Winners Round 1",
        side: "winners",
        matches: w1,
        race_to: races.winners
      },
      %{
        code: "W2",
        name: "Winners Round 2",
        side: "winners",
        matches: w2,
        race_to: races.winners
      },
      %{code: "L1", name: "Losers Round 1", side: "losers", matches: w2, race_to: races.losers},
      %{code: "L2", name: "Losers Round 2", side: "losers", matches: w2, race_to: races.losers}
    ] ++ knockout_rounds(div(bracket, 2), races)
  end

  # The knockout starts with half the field — the unbeaten quarter plus the
  # one-loss quarter — and halves from there down to the final.
  defp knockout_rounds(players, races) do
    players
    |> Stream.iterate(&div(&1, 2))
    |> Enum.take_while(&(&1 >= 2))
    |> Enum.map(fn n ->
      %{
        code: knockout_code(n),
        name: knockout_name(n),
        side: "knockout",
        matches: div(n, 2),
        race_to: knockout_race(n, races)
      }
    end)
  end

  defp knockout_code(2), do: "F"
  defp knockout_code(4), do: "SF"
  defp knockout_code(8), do: "QF"
  defp knockout_code(n), do: "R#{n}"

  defp knockout_name(2), do: "Final"
  defp knockout_name(4), do: "Semifinals"
  defp knockout_name(8), do: "Quarterfinals"
  defp knockout_name(n), do: "Round of #{n}"

  defp knockout_race(2, races), do: races.final
  defp knockout_race(4, races), do: races.semifinal
  defp knockout_race(_n, races), do: races.knockout

  # ---------------------------------------------------------------- fixtures

  defp build_fixtures(bracket, slots) do
    w2 = div(bracket, 4)
    first_knockout = knockout_code(div(bracket, 2))

    Enum.concat([
      w1_fixtures(bracket, slots),
      w2_fixtures(w2, first_knockout),
      l1_fixtures(w2),
      l2_fixtures(w2, first_knockout),
      List.flatten(knockout_fixtures(div(bracket, 2)))
    ])
  end

  defp w1_fixtures(bracket, slots) do
    bracket
    |> seed_pairs()
    |> Enum.with_index(1)
    |> Enum.map(fn {{high, low}, k} ->
      a = Map.fetch!(slots, high)
      b = Map.fetch!(slots, low)

      %{
        code: "W1-#{k}",
        round_code: "W1",
        slot: k,
        a: entrant(a),
        b: entrant(b),
        a_seed: high,
        b_seed: low,
        bye: a == :bye or b == :bye,
        winner_to: {"W2-#{feed(k)}", feed_side(k)},
        # A bye produces no loser, so nothing is routed into the losers'
        # bracket from here — the slot stays empty and its losers' match
        # becomes a walkover for whoever does turn up.
        loser_to: if(a == :bye or b == :bye, do: nil, else: {"L1-#{feed(k)}", feed_side(k)})
      }
    end)
  end

  defp w2_fixtures(w2, first_knockout) do
    for k <- 1..w2 do
      %{
        code: "W2-#{k}",
        round_code: "W2",
        slot: k,
        a: nil,
        b: nil,
        bye: false,
        winner_to: {"#{first_knockout}-#{k}", :a},
        # Mirrored: the W2-1 loser drops to the far end of the crossover, and
        # into slot A — whoever arrives from the winners' side is shown on top
        # of a crossover card, so the chart reads the same way every time.
        loser_to: {"L2-#{w2 + 1 - k}", :a}
      }
    end
  end

  defp l1_fixtures(w2) do
    for k <- 1..w2 do
      %{
        code: "L1-#{k}",
        round_code: "L1",
        slot: k,
        a: nil,
        b: nil,
        bye: false,
        # Slot B: the winners'-side dropper takes the top of the card.
        winner_to: {"L2-#{k}", :b},
        loser_to: nil
      }
    end
  end

  defp l2_fixtures(w2, first_knockout) do
    half = div(w2, 2)

    for k <- 1..w2 do
      %{
        code: "L2-#{k}",
        round_code: "L2",
        slot: k,
        a: nil,
        b: nil,
        bye: false,
        winner_to: {"#{first_knockout}-#{rotate(k, half, w2)}", :b},
        loser_to: nil
      }
    end
  end

  defp knockout_fixtures(players) do
    players
    |> Stream.iterate(&div(&1, 2))
    |> Enum.take_while(&(&1 >= 2))
    |> Enum.map(fn n ->
      code = knockout_code(n)
      next = knockout_code(div(n, 2))

      for k <- 1..div(n, 2) do
        %{
          code: "#{code}-#{k}",
          round_code: code,
          slot: k,
          a: nil,
          b: nil,
          bye: false,
          winner_to: if(n > 2, do: {"#{next}-#{feed(k)}", feed_side(k)}),
          loser_to: nil
        }
      end
    end)
  end

  # Two matches feed one: 1 and 2 -> 1, 3 and 4 -> 2 …
  defp feed(k), do: div(k + 1, 2)
  defp feed_side(k), do: if(rem(k, 2) == 1, do: :a, else: :b)

  # Rotate k by `half` within 1..n — the knockout offset.
  defp rotate(k, half, n), do: rem(k - half - 1 + n, n) + 1

  defp entrant(:bye), do: :bye
  defp entrant(other), do: other
end
