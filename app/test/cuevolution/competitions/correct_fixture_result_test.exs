defmodule Cuevolution.Competitions.CorrectFixtureResultTest do
  @moduledoc """
  A tournament director can edit a result after the match is finished, and the
  bracket moves with the correction — unless a later match has already been
  played.
  """
  use Cuevolution.DataCase, async: true

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp played_opener(count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: "male")
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, "male", admin)

    fixture =
      Repo.one!(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 1
      )

    {:ok, _} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })

    %{bracket: bracket, admin: admin, fixture: Repo.get!(Fixture, fixture.id)}
  end

  describe "correcting the score" do
    test "a mistyped score can be fixed after completion", %{} do
      %{admin: admin, fixture: fixture} = played_opener()

      assert {:ok, result} =
               Competitions.correct_fixture_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id,
                 "score" => %{"a" => 6, "b" => 4}
               })

      assert result.score == %{"a" => 6, "b" => 4}
      assert result.winner_participation_id == fixture.participant_a_id
    end

    test "the previous value is kept for the audit trail" do
      %{admin: admin, fixture: fixture} = played_opener()

      {:ok, result} =
        Competitions.correct_fixture_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 5}
        })

      assert result.prior_value["score"] == %{"a" => 6, "b" => 2}
    end

    test "the corrected frames reach the standings" do
      %{admin: admin, fixture: fixture} = played_opener()

      Competitions.correct_fixture_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id,
        "score" => %{"a" => 6, "b" => 5}
      })

      row =
        Competitions.standings_for_category("male")
        |> Enum.find(&(&1.id == fixture.participant_a_id))

      assert row.frames_won == 6
      assert row.frames_lost == 5
    end
  end

  describe "correcting the winner" do
    test "the next round is re-pointed at the corrected winner" do
      %{admin: admin, fixture: fixture} = played_opener()

      onward = Repo.get!(Fixture, fixture.winner_to_fixture_id)
      side = String.to_existing_atom("participant_#{fixture.winner_to_side}_id")
      assert Map.fetch!(onward, side) == fixture.participant_a_id

      assert {:ok, _result} =
               Competitions.correct_fixture_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_b_id,
                 "score" => %{"a" => 2, "b" => 6}
               })

      corrected = Repo.get!(Fixture, fixture.winner_to_fixture_id)
      assert Map.fetch!(corrected, side) == fixture.participant_b_id
    end

    test "it is refused once a later match has been played" do
      %{admin: admin, fixture: fixture} = played_opener()

      onward = Repo.get!(Fixture, fixture.winner_to_fixture_id) |> Repo.preload(:round)

      # Give the onward match an opponent and play it.
      other_side =
        if fixture.winner_to_side == "a", do: :participant_b_id, else: :participant_a_id

      opponent =
        insert(:stage_participation, stage_id: circuit().id, category: "male")

      onward =
        onward
        |> Ecto.Changeset.change(%{other_side => opponent.id})
        |> Repo.update!()

      {:ok, _} =
        Competitions.record_result(onward, admin, %{
          "winner_participation_id" => opponent.id,
          "score" => %{"a" => 6, "b" => 1}
        })

      assert {:error, :downstream_played} =
               Competitions.correct_fixture_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_b_id,
                 "score" => %{"a" => 2, "b" => 6}
               })
    end

    test "a score-only correction is still allowed once a later match is played" do
      %{admin: admin, fixture: fixture} = played_opener()

      onward = Repo.get!(Fixture, fixture.winner_to_fixture_id)

      other_side =
        if fixture.winner_to_side == "a", do: :participant_b_id, else: :participant_a_id

      opponent = insert(:stage_participation, stage_id: circuit().id, category: "male")

      onward =
        onward |> Ecto.Changeset.change(%{other_side => opponent.id}) |> Repo.update!()

      {:ok, _} =
        Competitions.record_result(onward, admin, %{
          "winner_participation_id" => opponent.id,
          "score" => %{"a" => 6, "b" => 1}
        })

      # The winner is unchanged, so there is nothing downstream to re-point.
      assert {:ok, result} =
               Competitions.correct_fixture_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id,
                 "score" => %{"a" => 6, "b" => 3}
               })

      assert result.score == %{"a" => 6, "b" => 3}
    end
  end

  describe "who may correct" do
    test "a venue representative may not" do
      %{fixture: fixture} = played_opener()
      rep = insert(:admin, role: "venue_representative")

      assert {:error, :unauthorized} =
               Competitions.correct_fixture_result(fixture, rep, %{
                 "winner_participation_id" => fixture.participant_a_id,
                 "score" => %{"a" => 6, "b" => 0}
               })
    end

    test "a match with no result cannot be corrected" do
      %{admin: admin, bracket: bracket} = played_opener()

      unplayed =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where:
              r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 2 and
                is_nil(f.result_id),
            limit: 1
        )

      assert {:error, :not_recorded} =
               Competitions.correct_fixture_result(unplayed, admin, %{
                 "winner_participation_id" => unplayed.participant_a_id,
                 "score" => %{"a" => 6, "b" => 0}
               })
    end
  end
end
