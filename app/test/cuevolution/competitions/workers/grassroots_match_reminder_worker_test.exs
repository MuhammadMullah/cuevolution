defmodule Cuevolution.Competitions.Workers.GrassrootsMatchReminderWorkerTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{MatchResult, Stage}
  alias Cuevolution.Competitions.Workers.GrassrootsMatchReminderWorker
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo

  test "notifies players with scheduled Grassroots fixtures and fewer than half played there" do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    regional = Repo.get_by!(Stage, name: "Regional")

    grassroots =
      Repo.update!(
        Ecto.Changeset.change(grassroots, completion_deadline: Date.add(Date.utc_today(), 2))
      )

    target = insert(:player, notification_preference: "both")

    target_participation =
      insert(:stage_participation,
        player_id: target.id,
        region_id: target.region_id,
        stage_id: grassroots.id,
        category: "male"
      )

    add_played_fixture(target_participation, grassroots, "verified")

    for _ <- 1..3 do
      add_played_fixture(target_participation, regional, "verified")
    end

    add_scheduled_fixture(target_participation, grassroots)
    add_scheduled_fixture(target_participation, grassroots)

    no_played_player = insert(:player, notification_preference: "email")
    no_played_participation = insert(:stage_participation, player_id: no_played_player.id)
    add_scheduled_fixture(no_played_participation, grassroots)

    backlog_ids = Enum.map(Competitions.players_with_grassroots_match_backlog(), & &1.id)
    assert target.id in backlog_ids
    assert no_played_player.id in backlog_ids
    assert length(backlog_ids) == 5

    assert :ok = GrassrootsMatchReminderWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 12

    assert Enum.any?(
             Repo.all(
               from n in Notification,
                 where:
                   n.player_id == ^target.id and
                     n.event_type == "grassroots_match_reminder" and n.channel == "email"
             ),
             &(&1.payload["deadline"] == Date.to_iso8601(grassroots.completion_deadline))
           )

    assert :ok = GrassrootsMatchReminderWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 12
  end

  test "does not notify when the deadline has passed" do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")

    Repo.update!(
      Ecto.Changeset.change(grassroots, completion_deadline: Date.add(Date.utc_today(), -1))
    )

    player = insert(:player)
    participation = insert(:stage_participation, player_id: player.id, stage_id: grassroots.id)
    add_played_fixture(participation, grassroots, "verified")
    add_scheduled_fixture(participation, grassroots)

    assert :ok = GrassrootsMatchReminderWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 0
  end

  test "does not include a player who has played exactly half of their Grassroots fixtures" do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")

    Repo.update!(
      Ecto.Changeset.change(grassroots, completion_deadline: Date.add(Date.utc_today(), 2))
    )

    player = insert(:player)
    participation = insert(:stage_participation, player_id: player.id, stage_id: grassroots.id)
    add_played_fixture(participation, grassroots, "verified")
    add_scheduled_fixture(participation, grassroots)

    refute player.id in Enum.map(Competitions.players_with_grassroots_match_backlog(), & &1.id)
  end

  defp add_played_fixture(participation, stage, status) do
    opponent =
      insert(:stage_participation, stage_id: stage.id, region_id: participation.region_id)

    round = insert(:round, stage_id: stage.id)

    fixture =
      insert(:fixture,
        round_id: round.id,
        participant_a_id: participation.id,
        participant_b_id: opponent.id,
        venue_id: insert(:venue, region_id: participation.region_id).id,
        status: status
      )

    Repo.insert!(%MatchResult{
      fixture_id: fixture.id,
      winner_participation_id: participation.id,
      recorded_by_admin_id: insert(:admin).id
    })
  end

  defp add_scheduled_fixture(participation, stage) do
    opponent =
      insert(:stage_participation, stage_id: stage.id, region_id: participation.region_id)

    round = insert(:round, stage_id: stage.id)

    insert(:fixture,
      round_id: round.id,
      participant_a_id: participation.id,
      participant_b_id: opponent.id,
      venue_id: insert(:venue, region_id: participation.region_id).id,
      status: "scheduled"
    )
  end
end
