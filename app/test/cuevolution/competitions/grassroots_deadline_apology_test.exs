defmodule Cuevolution.Competitions.GrassrootsDeadlineApologyTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions.GrassrootsDeadlineApology
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo

  test "dry run targets only non-anonymized male Grassroots players" do
    grassroots = Repo.get_by!(Cuevolution.Competitions.Stage, name: "Grassroots")
    male = insert(:player, notification_preference: "email")
    female = insert(:player, notification_preference: "email")

    anonymized =
      insert(:player, notification_preference: "email", anonymized_at: DateTime.utc_now())

    insert(:stage_participation, player_id: male.id, stage_id: grassroots.id, category: "male")

    insert(:stage_participation,
      player_id: female.id,
      stage_id: grassroots.id,
      category: "female"
    )

    insert(:stage_participation,
      player_id: anonymized.id,
      stage_id: grassroots.id,
      category: "male"
    )

    assert %{dry_run: true, targeted: 1, batches: 1} = GrassrootsDeadlineApology.run()
    assert Repo.aggregate(Notification, :count, :id) == 0
  end

  test "dispatches idempotently to male Grassroots players using their preference" do
    grassroots = Repo.get_by!(Cuevolution.Competitions.Stage, name: "Grassroots")
    player = insert(:player, notification_preference: "both")

    insert(:stage_participation,
      player_id: player.id,
      stage_id: grassroots.id,
      category: "male"
    )

    assert %{dry_run: false, targeted: 1, batches: 1} =
             GrassrootsDeadlineApology.run(dry_run: false, batch_delay_ms: 0)

    assert Repo.aggregate(Notification, :count, :id) == 2

    assert Enum.all?(Repo.all(Notification), fn notification ->
             notification.event_type == "grassroots_deadline_apology" and
               notification.payload["deadline"] == "11 October 2026"
           end)

    GrassrootsDeadlineApology.run(dry_run: false, batch_delay_ms: 0)
    assert Repo.aggregate(Notification, :count, :id) == 2
  end
end
