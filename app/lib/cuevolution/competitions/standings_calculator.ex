defmodule Cuevolution.Competitions.StandingsCalculator do
  @moduledoc """
  Pure, DB-free standings tiebreaker cascade (spec 008 FR-013) — the single
  most important module in the Competitions context, since it decides who
  advances and who's eliminated. Applies at both Grassroots and Regional
  group standings (`Competitions.group_standings/1`/`top_advancers/1` are
  the query-wrapping layer that feeds this real data); this module never
  touches `Repo` or any Ecto schema.

  The default cascade is (1) match wins, (2) head-to-head result among
  still-tied participants, (3) frame/rack differential, (4) total frames
  won. The `:points_first` cascade used by Grassroots is (1) total points,
  (2) head-to-head result, (3) match wins, (4) frame differential. Participants
  tied after the configured levels are returned with `tied: true` rather than
  silently ordered by an arbitrary rule.
  """

  @type match :: %{
          winner_id: term(),
          participant_a_id: term(),
          participant_b_id: term(),
          frames_won_a: non_neg_integer(),
          frames_won_b: non_neg_integer()
        }

  @type standing :: %{
          participant_id: term(),
          rank: pos_integer(),
          points: non_neg_integer(),
          bonus: non_neg_integer(),
          wins: non_neg_integer(),
          losses: non_neg_integer(),
          frame_diff: integer(),
          frames_won: non_neg_integer(),
          tied: boolean()
        }

  @doc """
  Ranks `participant_ids` (every participant who should appear, including
  byes with zero matches played) using `matches` (already scoped to one
  group — this function has no notion of "group" itself).

  Returns a list of `t:standing/0`, highest-ranked first. Participants tied
  after every tiebreaker level share consecutive ranks and are marked
  `tied: true` — the admin resolves the remaining ambiguity manually rather
  than the system silently guessing an order.
  """
  @spec rank([term()], [match()]) :: [standing()]
  def rank(participant_ids, matches), do: rank(participant_ids, matches, cascade: :wins_first)

  @spec rank([term()], [match()], keyword()) :: [standing()]
  def rank(participant_ids, matches, opts) do
    cascade = Keyword.get(opts, :cascade, :wins_first)
    stats = Map.new(participant_ids, &{&1, build_stat(&1, matches)})

    ranked =
      case cascade do
        :wins_first ->
          participant_ids
          |> Enum.uniq()
          |> Enum.group_by(&stats[&1].wins)
          |> Enum.sort_by(fn {wins, _ids} -> -wins end)
          |> Enum.flat_map(fn {_wins, tier} ->
            resolve_tier(tier, stats, matches, :wins_first)
          end)
          |> assign_ranks()

        :points_first ->
          participant_ids
          |> Enum.uniq()
          |> Enum.group_by(&stats[&1].points)
          |> Enum.sort_by(fn {points, _ids} -> -points end)
          |> Enum.flat_map(fn {_points, tier} ->
            resolve_tier(tier, stats, matches, :points_first)
          end)
          |> assign_ranks()

        invalid ->
          raise ArgumentError, "unsupported standings cascade: #{inspect(invalid)}"
      end

    ranked
    |> apply_tie_breakers(Keyword.get(opts, :tie_breakers, []))
    |> assign_ranks()
  end

  defp build_stat(participant_id, matches) do
    totals =
      Enum.reduce(
        matches,
        %{wins: 0, losses: 0, frames_won: 0, frames_lost: 0, points: 0, bonus: 0},
        fn match, acc ->
          cond do
            match.participant_a_id == participant_id ->
              acc
              |> add_frames(match.frames_won_a, match.frames_won_b)
              |> add_result(match.winner_id == participant_id)
              |> add_points(points_for(match, :a), bonus_for(match, :a))

            match.participant_b_id == participant_id ->
              acc
              |> add_frames(match.frames_won_b, match.frames_won_a)
              |> add_result(match.winner_id == participant_id)
              |> add_points(points_for(match, :b), bonus_for(match, :b))

            true ->
              acc
          end
        end
      )

    Map.put(totals, :frame_diff, totals.frames_won - totals.frames_lost)
  end

  defp add_frames(acc, won, lost),
    do: %{acc | frames_won: acc.frames_won + won, frames_lost: acc.frames_lost + lost}

  defp add_result(acc, true), do: %{acc | wins: acc.wins + 1}
  defp add_result(acc, false), do: %{acc | losses: acc.losses + 1}

  defp add_points(acc, points, bonus),
    do: %{acc | points: acc.points + points, bonus: acc.bonus + bonus}

  defp points_for(match, :a) do
    case Map.get(match, :points_a) do
      nil ->
        frames_won = match.frames_won_a
        frames_lost = match.frames_won_b
        frames_won + inferred_bonus(match, frames_won, frames_lost)

      points ->
        points
    end
  end

  defp points_for(match, :b) do
    case Map.get(match, :points_b) do
      nil ->
        frames_won = match.frames_won_b
        frames_lost = match.frames_won_a
        frames_won + inferred_bonus(match, frames_won, frames_lost)

      points ->
        points
    end
  end

  defp bonus_for(match, :a) do
    case Map.get(match, :bonus_a) do
      nil -> inferred_bonus(match, match.frames_won_a, match.frames_won_b)
      bonus -> bonus
    end
  end

  defp bonus_for(match, :b) do
    case Map.get(match, :bonus_b) do
      nil -> inferred_bonus(match, match.frames_won_b, match.frames_won_a)
      bonus -> bonus
    end
  end

  defp inferred_bonus(match, 5, 0) do
    if Map.get(match, :status) in [:walkover, "walkover"], do: 0, else: 1
  end

  defp inferred_bonus(_match, _frames_won, _frames_lost), do: 0

  # Level 1 (wins) tiers land here. A singleton tier needs no further
  # tiebreaking; a multi-participant tier proceeds to head-to-head.
  defp resolve_tier([single], stats, _matches, _cascade), do: [finalize(single, stats, false)]

  defp resolve_tier(tier, stats, matches, cascade) do
    tier
    |> Enum.group_by(&head_to_head_wins(&1, tier, matches))
    |> Enum.sort_by(fn {h2h, _ids} -> -h2h end)
    |> Enum.flat_map(fn {_h2h, sub_tier} ->
      case cascade do
        :wins_first -> resolve_by_frame_diff(sub_tier, stats)
        :points_first -> resolve_by_wins_then_frame_diff(sub_tier, stats)
      end
    end)
  end

  defp resolve_by_wins_then_frame_diff([single], stats), do: [finalize(single, stats, false)]

  defp resolve_by_wins_then_frame_diff(tier, stats) do
    tier
    |> Enum.group_by(&stats[&1].wins)
    |> Enum.sort_by(fn {wins, _ids} -> -wins end)
    |> Enum.flat_map(fn {_wins, sub_tier} ->
      resolve_by_frame_diff_without_frames_won(sub_tier, stats)
    end)
  end

  defp resolve_by_frame_diff_without_frames_won([single], stats),
    do: [finalize(single, stats, false)]

  defp resolve_by_frame_diff_without_frames_won(tier, stats) do
    tier
    |> Enum.group_by(&stats[&1].frame_diff)
    |> Enum.sort_by(fn {diff, _ids} -> -diff end)
    |> Enum.flat_map(fn {_diff, ids} ->
      tied? = length(ids) > 1
      Enum.map(ids, &finalize(&1, stats, tied?))
    end)
  end

  # Wins credited only for results against OTHER MEMBERS of this exact
  # win-count tier — a participant's wins against opponents outside the tier
  # are already reflected in the win-count level and shouldn't double-count.
  defp head_to_head_wins(participant_id, tier, matches) do
    tier_set = MapSet.new(tier)

    Enum.count(matches, fn match ->
      match.winner_id == participant_id and
        ((match.participant_a_id == participant_id and
            MapSet.member?(tier_set, match.participant_b_id)) or
           (match.participant_b_id == participant_id and
              MapSet.member?(tier_set, match.participant_a_id)))
    end)
  end

  defp resolve_by_frame_diff([single], stats), do: [finalize(single, stats, false)]

  defp resolve_by_frame_diff(sub_tier, stats) do
    sub_tier
    |> Enum.group_by(&stats[&1].frame_diff)
    |> Enum.sort_by(fn {diff, _ids} -> -diff end)
    |> Enum.flat_map(fn {_diff, group} -> resolve_by_frames_won(group, stats) end)
  end

  defp resolve_by_frames_won([single], stats), do: [finalize(single, stats, false)]

  defp resolve_by_frames_won(group, stats) do
    group
    |> Enum.group_by(&stats[&1].frames_won)
    |> Enum.sort_by(fn {won, _ids} -> -won end)
    |> Enum.flat_map(fn {_total, ids} ->
      tied? = length(ids) > 1
      Enum.map(ids, &finalize(&1, stats, tied?))
    end)
  end

  defp finalize(participant_id, stats, tied?) do
    Map.merge(%{participant_id: participant_id, tied: tied?}, stats[participant_id])
  end

  defp apply_tie_breakers(rows, []), do: rows

  defp apply_tie_breakers(rows, tie_breakers) do
    overrides = Map.new(tie_breakers, fn [winner, loser] -> {winner, loser} end)

    resolved_ids =
      tie_breakers
      |> Enum.flat_map(fn [winner, loser] -> [winner, loser] end)
      |> MapSet.new()

    Enum.map(rows, fn row ->
      if row.tied and MapSet.member?(resolved_ids, to_string(row.participant_id)) do
        %{row | tied: false}
      else
        row
      end
    end)
    |> Enum.sort_by(fn row ->
      case Map.get(overrides, to_string(row.participant_id)) do
        nil -> {row.rank, 1}
        _loser -> {row.rank, 0}
      end
    end)
  end

  defp assign_ranks(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} -> Map.put(entry, :rank, index) end)
  end
end
