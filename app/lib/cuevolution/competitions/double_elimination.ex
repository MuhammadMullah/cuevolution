defmodule Cuevolution.Competitions.DoubleElimination do
  @moduledoc """
  Builds the Circuit stage bracket as plain data — no `Repo`, no side effects.

  Double elimination runs for `depth` winners' rounds, then the survivors —
  the still-unbeaten half of the winners' side plus the one-loss half of the
  losers' side — play straight single elimination to a champion.

  **Men (SP Points & Standings brief, Nov 2026): `depth: 3`.** A 128 draw runs
  WB R1-R3 and LB R1-R4, leaving 32 players (16 a side) for the single
  elimination:

      WB R1  128 -> 64   losers to LB R1
      WB R2   64 -> 32   losers to LB R2
      WB R3   32 -> 16   losers to LB R4, winners to the last 32
      LB R1   64 -> 32   losers out, 97-128
      LB R2   64 -> 32   losers out,  65-96   (LB R1 winners + WB R2 losers)
      LB R3   32 -> 16   losers out,  49-64
      LB R4   32 -> 16   losers out,  33-48   (LB R3 winners + WB R3 losers)
      Last 32 onwards    single elimination

  **Ladies: `depth: 2`,** the shallower bracket that was in use before the
  brief. The brief leaves the 48-player ladies format open, so this is
  deliberately unchanged until it is decided — see `@formats`.

  Three pairing rules, in each case chosen so a player does not immediately
  meet somebody they have just played:

    * **Seeding** is the standard recursive bracket order — 1 v 128, 64 v 65,
      32 v 97, 33 v 96 … (`seed_order/1`).
    * **Every crossover is mirrored**: the losers of `Wi` enter `L(2i-2)` from
      the far end, in slot A, so the winners'-side dropper is always on top of
      the card.
    * **The single-elimination draw is offset by half a round**: the `L(2d-2)`
      winners are rotated against the `Wd` winners. Pairing them straight
      across would put a player back in against someone they knocked out in
      WB R1. `double_elimination_test.exs` asserts no first-round rematch for
      a full 128 draw.

  The brief lists the last-32 draw as an open item ("are winners'-side
  qualifiers paired against losers'-side qualifiers?"), so the rotation here is
  a defensible default rather than a confirmed rule.

  `build/2` returns `%{rounds: [...], fixtures: [...]}` where each fixture
  carries where its winner goes and where its loser goes, as
  `{fixture_code, :a | :b}` or `nil` for "eliminated". Persisting that graph is
  `Competitions.generate_circuit_bracket/4`'s job, not this module's.
  """

  import Bitwise, only: [bsl: 2]

  # Race lengths from the format sheet: the men play a race to 6 from the
  # round of 128 down to the semifinals, with two exceptions — the losers'
  # side is shorter at 5, and the final is longer at 7. The sheet names no
  # other exception, so the semifinal runs at the knockout length.
  @formats %{
    "male" => %{
      depth: 3,
      races: %{winners: 6, losers: 5, knockout: 6, semifinal: 6, final: 7}
    },
    "female" => %{
      depth: 2,
      races: %{winners: 4, losers: 3, knockout: 4, semifinal: 4, final: 5}
    }
  }

  @doc ~S(The bracket format for `category` — `%{depth: n, races: map}`.)
  def format_for(category) when is_map_key(@formats, category),
    do: Map.fetch!(@formats, category)

  @doc ~S(The official race lengths for `category` — "male" or "female".)
  def races_for(category), do: format_for(category).races

  @doc """
  Builds the full bracket for `entrants` (a list of anything — participation
  ids, seeds, structs — in seeding order, best first).

  Options:

    * `:category` — `"male"` (default) or `"female"`, which selects that
      event's bracket depth and race lengths.
    * `:depth` — how many winners' rounds run before the single elimination,
      overriding the category's. 3 leaves a last 32 from a 128 draw, 2 a
      last 64.
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
    format = format_for(Keyword.get(opts, :category, "male"))
    races = Map.merge(format.races, Map.new(Keyword.get(opts, :races, %{})))

    if bracket < 8 do
      raise ArgumentError, "a Circuit bracket needs at least 5 entrants, got #{field}"
    end

    # The format's depth is what a full field plays. A smaller draw — a demo, a
    # regional one-off — cannot support three winners' rounds and still have a
    # final left, so it runs the deepest double elimination it has room for
    # rather than refusing to draw at all.
    depth = min(Keyword.get(opts, :depth, format.depth), max_depth(bracket))

    slots = assign_slots(entrants, bracket, opts)

    %{
      rounds: build_rounds(bracket, depth, races),
      fixtures: build_fixtures(bracket, depth, slots),
      bracket_size: bracket,
      depth: depth,
      byes: bracket - field,
      qualifiers: single_elimination_size(bracket, depth)
    }
  end

  @doc """
  The deepest double elimination a `bracket` can run and still have a final:
  each winners' round halves the field, and the single elimination needs at
  least two players at the end of it.
  """
  def max_depth(bracket), do: max(trunc(:math.log2(bracket)) - 1, 1)

  @doc "How many players reach the single-elimination phase of a `bracket`."
  def single_elimination_size(bracket, depth), do: div(bracket, bsl(1, depth - 1))

  @doc "How many losers' rounds a depth-`depth` bracket has."
  def losers_round_count(depth), do: 2 * depth - 2

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

  defp build_rounds(bracket, depth, races) do
    winners =
      for i <- 1..depth do
        %{
          code: "W#{i}",
          name: "Winners Round #{i}",
          side: "winners",
          matches: winners_matches(bracket, i),
          race_to: races.winners
        }
      end

    losers =
      for j <- 1..losers_round_count(depth) do
        %{
          code: "L#{j}",
          name: "Losers Round #{j}",
          side: "losers",
          matches: losers_matches(bracket, j),
          race_to: races.losers
        }
      end

    winners ++ losers ++ knockout_rounds(single_elimination_size(bracket, depth), races)
  end

  # `Wi` is the i-th halving of the field, so it has bracket / 2^i matches.
  defp winners_matches(bracket, i), do: div(bracket, bsl(1, i))

  # The losers' side alternates: an odd round pairs up the survivors it already
  # has, and the even round after it takes in that winners' round's droppers.
  # Both rounds of a pair are the same size, which is why the index is halved.
  defp losers_matches(bracket, j), do: div(bracket, bsl(1, div(j + 1, 2) + 1))

  # The single elimination starts with the unbeaten side plus the one-loss
  # side, and halves from there down to the final.
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

  defp build_fixtures(bracket, depth, slots) do
    se = single_elimination_size(bracket, depth)
    first = knockout_code(se)

    Enum.concat([
      w1_fixtures(bracket, depth, slots, first),
      Enum.flat_map(2..depth//1, &wn_fixtures(bracket, depth, &1, first)),
      Enum.flat_map(1..losers_round_count(depth)//1, &ln_fixtures(bracket, depth, &1, first)),
      List.flatten(knockout_fixtures(se))
    ])
  end

  defp w1_fixtures(bracket, depth, slots, first) do
    bracket
    |> seed_pairs()
    |> Enum.with_index(1)
    |> Enum.map(fn {{high, low}, k} ->
      a = Map.fetch!(slots, high)
      b = Map.fetch!(slots, low)
      bye? = a == :bye or b == :bye

      %{
        code: "W1-#{k}",
        round_code: "W1",
        slot: k,
        a: entrant(a),
        b: entrant(b),
        a_seed: high,
        b_seed: low,
        bye: bye?,
        winner_to: winners_winner_to(depth, 1, k, first),
        # A bye produces no loser, so nothing is routed into the losers'
        # bracket from here — the slot stays empty and its losers' match
        # becomes a walkover for whoever does turn up.
        loser_to: unless(bye?, do: {"L1-#{feed(k)}", feed_side(k)})
      }
    end)
  end

  # Winners' rounds 2..depth. The last one sends its winners into the single
  # elimination; the rest feed the next winners' round. Losers always drop into
  # the crossover round `L(2i-2)`, mirrored and in slot A so the
  # winners'-side player sits on top of the card.
  defp wn_fixtures(bracket, depth, i, first) do
    matches = winners_matches(bracket, i)
    crossover = 2 * i - 2

    for k <- 1..matches do
      %{
        code: "W#{i}-#{k}",
        round_code: "W#{i}",
        slot: k,
        a: nil,
        b: nil,
        bye: false,
        winner_to: winners_winner_to(depth, i, k, first),
        loser_to: {"L#{crossover}-#{matches + 1 - k}", :a}
      }
    end
  end

  defp winners_winner_to(depth, depth, k, first), do: {"#{first}-#{k}", :a}
  defp winners_winner_to(_depth, i, k, _first), do: {"W#{i + 1}-#{feed(k)}", feed_side(k)}

  # Losers' rounds. An odd round pairs up whoever is already there; the even
  # round after it is the crossover that takes the winners'-side droppers into
  # slot A, so these winners take slot B at the same index.
  defp ln_fixtures(bracket, depth, j, first) do
    last = losers_round_count(depth)
    matches = losers_matches(bracket, j)
    half = div(matches, 2)

    for k <- 1..matches do
      %{
        code: "L#{j}-#{k}",
        round_code: "L#{j}",
        slot: k,
        a: nil,
        b: nil,
        bye: false,
        winner_to: losers_winner_to(j, last, k, half, matches, first),
        # Every losers'-round defeat is a second loss: out.
        loser_to: nil
      }
    end
  end

  # The last losers' round feeds the single elimination, rotated by half a
  # round against the winners' qualifiers so nobody immediately replays the
  # match that put them here.
  defp losers_winner_to(last, last, k, half, matches, first),
    do: {"#{first}-#{rotate(k, half, matches)}", :b}

  defp losers_winner_to(j, _last, k, _half, _matches, _first) when rem(j, 2) == 1,
    do: {"L#{j + 1}-#{k}", :b}

  defp losers_winner_to(j, _last, k, _half, _matches, _first),
    do: {"L#{j + 1}-#{feed(k)}", feed_side(k)}

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
