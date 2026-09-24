defmodule Cuevolution.Competitions.StructuredMatchEntryTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Fixture, MatchFrame, MatchResult}

  describe "record_frames/3 and verify_result/3" do
    test "records five frames as completed, then exposes the result only after verification" do
      fixture =
        insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M1")
        |> Repo.preload([:participant_a, :participant_b])

      recorder = insert(:admin, role: "venue_representative")
      verifier = insert(:admin, role: "regional_coordinator")

      assert {:ok, result} =
               Competitions.record_frames(fixture, recorder, ["a", "a", "a", "b", "b"])

      assert result.winner_participation_id == fixture.participant_a_id
      assert Repo.aggregate(MatchFrame, :count, :id) == 5
      assert Repo.get!(Fixture, fixture.id).status == "completed"

      group =
        insert(:group,
          stage_id: fixture.participant_a.stage_id,
          category: fixture.participant_a.category
        )

      insert(:group_membership,
        group_id: group.id,
        stage_participation_id: fixture.participant_a_id
      )

      insert(:group_membership,
        group_id: group.id,
        stage_participation_id: fixture.participant_b_id
      )

      round = Repo.get!(Cuevolution.Competitions.Round, fixture.round_id)
      Repo.update!(Ecto.Changeset.change(round, group_id: group.id))
      assert Competitions.group_standings(group) |> Enum.all?(&(&1.points == 0))

      completed = Repo.get!(Fixture, fixture.id)
      assert {:ok, verified} = Competitions.verify_result(completed, verifier)
      assert verified.status == "verified"
      assert Competitions.group_standings(group) |> Enum.any?(&(&1.points > 0))
    end

    test "enforces the permission split between recording and verification" do
      fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M2")
      recorder = insert(:admin, role: "venue_representative")

      assert {:ok, _result} = Competitions.record_frames(fixture, recorder, [:a, :a, :a, :b, :b])
      assert {:error, :unauthorized} = Competitions.verify_result(fixture, recorder)
      assert {:error, :unauthorized} = Competitions.postpone_fixture(fixture, recorder, "Rain")

      assert {:error, :unauthorized} =
               Competitions.process_withdrawal(
                 Repo.get!(Cuevolution.Competitions.StageParticipation, fixture.participant_a_id),
                 recorder
               )

      approval_admin = insert(:admin, role: "tournament_director")
      walkover_fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M13")

      assert {:error, :unauthorized} =
               Competitions.record_walkover(
                 walkover_fixture,
                 approval_admin,
                 walkover_fixture.participant_a_id
               )
    end
  end

  describe "walkovers and postponement" do
    test "records a single walkover without frames or a clean-sweep bonus" do
      fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M3")
      admin = insert(:admin, role: "venue_representative")

      assert {:ok, updated} =
               Competitions.record_walkover(fixture, admin, fixture.participant_a_id)

      assert updated.status == "walkover"
      assert updated.walkover_kind == "single"
      assert Repo.aggregate(MatchFrame, :count, :id) == 0

      result = Repo.get_by!(MatchResult, fixture_id: fixture.id)
      assert result.score["participant_a_frames"] == 5
      assert result.score["participant_b_frames"] == 0
    end

    test "requires a reason to postpone and can resume with approval permission" do
      fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M4")
      admin = insert(:admin, role: "regional_coordinator")

      assert {:error, :reason_required} = Competitions.postpone_fixture(fixture, admin, " ")
      assert {:ok, postponed} = Competitions.postpone_fixture(fixture, admin, "Venue unavailable")
      assert postponed.status == "postponed"
      assert {:ok, resumed} = Competitions.resume_fixture(postponed, admin)
      assert resumed.status == "scheduled"
    end
  end

  describe "process_withdrawal/2" do
    test "keeps played matches and converts the remaining schedule at fifty percent" do
      fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M8")
      withdrawn = Repo.preload(fixture, :participant_a).participant_a

      opponent =
        insert(:stage_participation, stage_id: withdrawn.stage_id, category: withdrawn.category)

      remaining =
        insert(:fixture,
          round_id: fixture.round_id,
          participant_a_id: withdrawn.id,
          participant_b_id: opponent.id,
          match_id: "SP26-NBO-MS-A-R1-M9"
        )

      admin = insert(:admin, role: "regional_coordinator")
      recorder = insert(:admin, role: "venue_representative")

      assert {:ok, _result} = Competitions.record_frames(fixture, recorder, [:a, :a, :a, :b, :b])
      assert {:ok, converted} = Competitions.process_withdrawal(withdrawn, admin)
      assert Enum.any?(converted, &(&1.id == remaining.id and &1.walkover_kind == "single"))
      assert Repo.get!(Fixture, fixture.id).status == "completed"
    end

    test "resets played results when fewer than half the fixtures are played" do
      fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M10")
      withdrawn = Repo.preload(fixture, :participant_a).participant_a

      opponent =
        insert(:stage_participation, stage_id: withdrawn.stage_id, category: withdrawn.category)

      remaining =
        insert(:fixture,
          round_id: fixture.round_id,
          participant_a_id: withdrawn.id,
          participant_b_id: opponent.id,
          match_id: "SP26-NBO-MS-A-R1-M11"
        )

      third_opponent =
        insert(:stage_participation, stage_id: withdrawn.stage_id, category: withdrawn.category)

      third =
        insert(:fixture,
          round_id: fixture.round_id,
          participant_a_id: withdrawn.id,
          participant_b_id: third_opponent.id,
          match_id: "SP26-NBO-MS-A-R1-M12"
        )

      admin = insert(:admin, role: "regional_coordinator")
      recorder = insert(:admin, role: "venue_representative")

      assert {:ok, _result} = Competitions.record_frames(fixture, recorder, [:a, :a, :a, :b, :b])
      assert {:ok, _fixtures} = Competitions.process_withdrawal(withdrawn, admin)
      assert Repo.get!(Fixture, fixture.id).status == "scheduled"
      assert Repo.get!(Fixture, fixture.id).result_id == nil
      assert Repo.get!(Fixture, remaining.id).status == "scheduled"
      assert Repo.get!(Fixture, third.id).status == "scheduled"
    end
  end
end
