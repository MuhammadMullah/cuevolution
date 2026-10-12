defmodule Cuevolution.Competitions.ResultsRecordingClosedTest do
  @moduledoc """
  The `:results_recording_closed` config is global
  (`Application.get_env/2`), so these tests mutate and restore it
  themselves — this file runs `async: false` so they never race another
  test's `record_result/3` call.
  """
  use Cuevolution.DataCase, async: false

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture

  setup do
    previous = Application.get_env(:cuevolution, :results_recording_closed)
    on_exit(fn -> Application.put_env(:cuevolution, :results_recording_closed, previous) end)
    :ok
  end

  defp set_closed(bool), do: Application.put_env(:cuevolution, :results_recording_closed, bool)

  describe "results_recording_closed?/0" do
    test "false when the switch is off" do
      set_closed(false)
      refute Competitions.results_recording_closed?()
    end

    test "true when the switch is on" do
      set_closed(true)
      assert Competitions.results_recording_closed?()
    end
  end

  describe "record_result/3, record_walkover/3 while recording is closed" do
    test "blocks a regional coordinator" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)
      fixture = insert(:fixture, venue_id: venue.id)
      coordinator = insert(:admin, role: "regional_coordinator", region_id: region.id)

      set_closed(true)

      assert {:error, :results_recording_closed} =
               Competitions.record_result(fixture, coordinator, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      refute Repo.get!(Fixture, fixture.id).result_id
    end

    test "blocks a venue representative recording a walkover" do
      venue = insert(:venue)
      fixture = insert(:fixture, venue_id: venue.id)
      rep = insert(:admin, role: "venue_representative", venue_id: venue.id)

      set_closed(true)

      assert {:error, :results_recording_closed} =
               Competitions.record_walkover(fixture, rep, fixture.participant_a_id)
    end

    test "still allows a tournament director" do
      fixture = insert(:fixture)
      director = insert(:admin, role: "tournament_director")

      set_closed(true)

      assert {:ok, result} =
               Competitions.record_result(fixture, director, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      assert result.fixture_id == fixture.id
    end

    test "still allows a super admin" do
      fixture = insert(:fixture)
      admin = insert(:admin, role: "super_admin")

      set_closed(true)

      assert {:ok, _result} =
               Competitions.record_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id
               })
    end
  end

  describe "correct_result/3 while recording is closed" do
    test "blocks a recorder-only admin even on their own still-pending result" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)
      fixture = insert(:fixture, venue_id: venue.id)
      coordinator = insert(:admin, role: "regional_coordinator", region_id: region.id)

      {:ok, result} =
        Competitions.record_result(fixture, coordinator, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      set_closed(true)

      assert {:error, :results_recording_closed} =
               Competitions.correct_result(result, coordinator, %{
                 "winner_participation_id" => fixture.participant_b_id
               })
    end

    test "still allows a tournament director to correct" do
      fixture = insert(:fixture)
      director = insert(:admin, role: "tournament_director")

      {:ok, result} =
        Competitions.record_result(fixture, director, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      set_closed(true)

      assert {:ok, corrected} =
               Competitions.correct_result(result, director, %{
                 "winner_participation_id" => fixture.participant_b_id
               })

      assert corrected.winner_participation_id == fixture.participant_b_id
    end
  end
end
