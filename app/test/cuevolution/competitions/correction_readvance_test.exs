defmodule Cuevolution.Competitions.CorrectionReadvanceTest do
  @moduledoc """
  Changing who won a bracket match must move the bracket, whichever screen
  the change was made from.

  This went wrong in production: only the Circuit screen's correction
  re-advanced, so a result amended from the results list left the **loser**
  standing in the next round while the scoreline showed the winner.
  """
  use Cuevolution.DataCase, async: true

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp played_opener do
    stage = circuit()
    admin = insert(:admin, role: "super_admin")

    for _ <- 1..16 do
      insert(:stage_participation, stage_id: stage.id, category: "male")
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, "male", admin)

    fixture =
      Repo.one!(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where:
            r.knockout_bracket_id == ^bracket.id and r.code == "W1" and f.bye == false and
              not is_nil(f.participant_a_id) and not is_nil(f.participant_b_id),
          limit: 1
      )

    {:ok, _} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })

    %{admin: admin, fixture: Repo.get!(Fixture, fixture.id)}
  end

  defp who_advanced(fixture) do
    onward = Repo.get!(Fixture, fixture.winner_to_fixture_id)
    Map.fetch!(onward, String.to_existing_atom("participant_#{fixture.winner_to_side}_id"))
  end

  describe "correcting the winner" do
    test "from the results list re-points the next round" do
      %{admin: admin, fixture: fixture} = played_opener()

      assert who_advanced(fixture) == fixture.participant_a_id

      # This is the path `/admin/results` uses — it used to leave the bracket
      # pointing at the old winner.
      {:ok, _} =
        Competitions.correct_result(Repo.preload(fixture, :result).result, admin, %{
          "winner_participation_id" => fixture.participant_b_id,
          "score" => %{"a" => 2, "b" => 6}
        })

      assert who_advanced(fixture) == fixture.participant_b_id,
             "the corrected winner should be the one standing in the next round"
    end

    test "the verify-final-score path cannot touch a Circuit match at all" do
      %{admin: admin, fixture: fixture} = played_opener()

      # That path validates against the older best-of-five format, so a
      # race-to-6 scoreline is refused outright. Worth pinning down: it means
      # the bracket bug could only ever have come from the results list, and
      # if the format check is ever relaxed this test fails and points at the
      # re-advance wiring that is now in place for it.
      assert {:error, :invalid_final_score} =
               Competitions.verify_final_score(fixture, admin, %{
                 "participant_a_frames" => 2,
                 "participant_b_frames" => 6
               })

      assert who_advanced(fixture) == fixture.participant_a_id
    end

    test "from the Circuit screen re-points the next round" do
      %{admin: admin, fixture: fixture} = played_opener()

      {:ok, _} =
        Competitions.correct_fixture_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_b_id,
          "score" => %{"a" => 2, "b" => 6}
        })

      assert who_advanced(fixture) == fixture.participant_b_id
    end

    test "a score-only correction leaves the bracket alone" do
      %{admin: admin, fixture: fixture} = played_opener()

      {:ok, _} =
        Competitions.correct_result(Repo.preload(fixture, :result).result, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 5}
        })

      assert who_advanced(fixture) == fixture.participant_a_id
    end

    test "the loser is re-pointed too, not just the winner" do
      %{admin: admin, fixture: fixture} = played_opener()

      losers_slot = fn ->
        onward = Repo.get!(Fixture, fixture.loser_to_fixture_id)
        Map.fetch!(onward, String.to_existing_atom("participant_#{fixture.loser_to_side}_id"))
      end

      assert losers_slot.() == fixture.participant_b_id

      {:ok, _} =
        Competitions.correct_result(Repo.preload(fixture, :result).result, admin, %{
          "winner_participation_id" => fixture.participant_b_id,
          "score" => %{"a" => 2, "b" => 6}
        })

      assert losers_slot.() == fixture.participant_a_id,
             "the new loser should have dropped to the losers' side"
    end
  end
end
