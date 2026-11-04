defmodule Cuevolution.Competitions.StandingsScopeTest do
  @moduledoc """
  The standings cover the Circuit and the Finals, and nothing earlier.

  Advancing a player **moves** their `StageParticipation` row to the next
  stage rather than creating a new one, so the row's id — and every fixture
  that ever referenced it — travels with them. Anything that counts a player's
  matches has to say which stage it means; matching on the participation id
  alone silently counts their whole career.
  """
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Stage

  defp played_regional_match do
    regional = Repo.get_by!(Stage, name: "Regional")
    admin = insert(:admin, role: "super_admin")

    a = insert(:stage_participation, stage_id: regional.id, category: "male")
    b = insert(:stage_participation, stage_id: regional.id, category: "male")

    group = insert(:group, stage_id: regional.id, category: "male", region_id: a.region_id)
    round = insert(:round, stage_id: regional.id, group_id: group.id, name: "Round 1")

    fixture =
      insert(:fixture, round_id: round.id, participant_a_id: a.id, participant_b_id: b.id)

    {:ok, _} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => a.id,
        "score" => %{"participant_a_frames" => 4, "participant_b_frames" => 1}
      })

    %{winner: a, loser: b}
  end

  defp advance_to_circuit(participations) do
    circuit = Repo.get_by!(Stage, name: "Circuit")

    for p <- participations do
      Repo.update!(Ecto.Changeset.change(p, stage_id: circuit.id))
    end
  end

  describe "a player advanced into the Circuit" do
    test "brings no matches, wins or frames with them" do
      %{winner: winner, loser: loser} = played_regional_match()
      advance_to_circuit([winner, loser])

      rows = Competitions.standings_for_category("male")
      row = Enum.find(rows, &(&1.id == winner.id))

      assert row, "the advanced player should appear in the table"

      # They have played no Circuit match, so the table must say so — even
      # though this very participation has a played Regional match attached.
      assert row.played == 0
      assert row.won == 0
      assert row.frames_won == 0
      assert row.frames_lost == 0
      assert row.sp_points == 0
    end

    test "their opponent's loss does not follow them either" do
      %{winner: winner, loser: loser} = played_regional_match()
      advance_to_circuit([winner, loser])

      row =
        Competitions.standings_for_category("male")
        |> Enum.find(&(&1.id == loser.id))

      assert row.played == 0
      assert row.lost == 0
      assert row.frames_lost == 0
    end

    test "a Circuit match played after advancing is counted" do
      %{winner: winner, loser: loser} = played_regional_match()
      advance_to_circuit([winner, loser])

      circuit = Repo.get_by!(Stage, name: "Circuit")
      admin = insert(:admin, role: "tournament_director")

      # Enough entrants for a draw, including the two who came up.
      for _ <- 1..14 do
        insert(:stage_participation, stage_id: circuit.id, category: "male")
      end

      {:ok, %{bracket: bracket}} =
        Competitions.draw_circuit_bracket(circuit.id, "male", admin)

      opener =
        Repo.one!(
          from f in Cuevolution.Competitions.Fixture,
            join: r in Cuevolution.Competitions.Round,
            on: r.id == f.round_id,
            where:
              r.knockout_bracket_id == ^bracket.id and r.code == "W1" and f.bye == false and
                not is_nil(f.participant_a_id) and not is_nil(f.participant_b_id),
            limit: 1
        )

      {:ok, _} =
        Competitions.record_result(opener, admin, %{
          "winner_participation_id" => opener.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      row =
        Competitions.standings_for_category("male")
        |> Enum.find(&(&1.id == opener.participant_a_id))

      assert row.played == 1, "a Circuit match should count"
      assert row.won == 1
      assert row.frames_won == 6
      assert row.frames_lost == 2
    end
  end

  describe "the per-circuit table" do
    test "is empty before a draw, however much history the entrants have" do
      %{winner: winner, loser: loser} = played_regional_match()
      advance_to_circuit([winner, loser])

      circuit = Repo.get_by!(Stage, name: "Circuit")

      # No draw has been made, so there is no circuit to have standings for.
      assert Competitions.circuit_standings(circuit.id, "male") == nil
    end
  end
end
