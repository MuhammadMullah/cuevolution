defmodule Cuevolution.Competitions.Workers.GrassrootsDeadlineWorkerTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.AdminActionLog
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Fixture, Group, MatchResult, Stage}
  alias Cuevolution.Competitions.Workers.GrassrootsDeadlineWorker
  alias Cuevolution.Repo

  defp overdue_group_fixture(status \\ "scheduled") do
    stage = Repo.get_by!(Stage, name: "Grassroots")
    stage = Repo.update!(Ecto.Changeset.change(stage, completion_deadline: ~D[2020-01-01]))
    region = build(:region)
    venue = insert(:venue, region_id: region.id)

    group =
      Repo.insert!(%Group{
        stage_id: stage.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Deadline Group"
      })

    a = insert(:stage_participation, stage_id: stage.id, region_id: region.id, category: "male")
    b = insert(:stage_participation, stage_id: stage.id, region_id: region.id, category: "male")
    {:ok, _} = Competitions.assign_to_group(a, group)
    {:ok, _} = Competitions.assign_to_group(b, group)
    round = insert(:round, stage_id: stage.id, group_id: group.id)

    insert(:fixture,
      round_id: round.id,
      participant_a_id: a.id,
      participant_b_id: b.id,
      venue_id: venue.id,
      status: status
    )
  end

  test "converts overdue scheduled fixtures to double walkovers and audits once" do
    fixture = overdue_group_fixture()

    assert :ok = GrassrootsDeadlineWorker.perform(%Oban.Job{})
    updated = Repo.get!(Fixture, fixture.id)
    assert updated.status == "walkover"
    assert updated.walkover_kind == "double"

    result = Repo.get!(MatchResult, updated.result_id)
    assert result.winner_participation_id == nil
    assert result.recorded_by_admin_id == nil
    assert result.score["points_a"] == 0

    assert Repo.aggregate(AdminActionLog, :count, :id) == 1

    assert Repo.get_by!(AdminActionLog, action_type: "deadline_double_walkover").actor_type ==
             "system"

    assert :ok = GrassrootsDeadlineWorker.perform(%Oban.Job{})
    assert Repo.aggregate(AdminActionLog, :count, :id) == 1
  end

  test "does not touch postponed fixtures" do
    fixture = overdue_group_fixture("postponed")

    assert :ok = GrassrootsDeadlineWorker.perform(%Oban.Job{})
    assert Repo.get!(Fixture, fixture.id).status == "postponed"
    assert Repo.aggregate(AdminActionLog, :count, :id) == 0
  end
end
