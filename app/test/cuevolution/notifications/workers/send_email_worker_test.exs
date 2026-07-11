defmodule Cuevolution.Notifications.Workers.SendEmailWorkerTest do
  use Cuevolution.DataCase, async: true

  import Swoosh.TestAssertions

  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Notifications.Workers.SendEmailWorker
  alias Cuevolution.Repo

  test "sends the registration-confirmation email and marks the notification sent" do
    player = insert(:player, notification_preference: "email")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    assert :ok = perform_job(SendEmailWorker, %{"notification_id" => notification.id})

    assert_email_sent(
      subject: "Welcome to Cuevolution!",
      to: [{"#{player.first_name} #{player.last_name}", player.email}]
    )

    assert Repo.get!(Notification, notification.id).status == "sent"
  end

  test "sends the fixture-assignment email with the fixture details" do
    player = insert(:player, notification_preference: "email")

    payload = %{
      opponent_name: "Jane Doe",
      venue: "Westlands Cue Club",
      date: "12 Jul",
      time: "3:00 PM"
    }

    [notification] = Notifications.dispatch(player, :fixture_assignment, payload)

    assert :ok = perform_job(SendEmailWorker, %{"notification_id" => notification.id})

    assert_email_sent(fn email ->
      email.subject =~ "Jane Doe" and email.html_body =~ "Westlands Cue Club"
    end)

    assert Repo.get!(Notification, notification.id).status == "sent"
  end

  test "sends the team-assignment email" do
    player = insert(:player, notification_preference: "email")
    payload = %{team_name: "The Sharks", captain_name: "Alex Otieno"}
    [notification] = Notifications.dispatch(player, :team_assignment, payload)

    assert :ok = perform_job(SendEmailWorker, %{"notification_id" => notification.id})

    assert_email_sent(fn email -> email.subject =~ "The Sharks" end)
    assert Repo.get!(Notification, notification.id).status == "sent"
  end

  test "a notification already claimed by another attempt is skipped, not re-sent (FR-009/SC-005)" do
    player = insert(:player, notification_preference: "email")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    # Simulate a previous attempt that claimed the row (transitioned it to
    # "sending") and then crashed before writing the final status.
    notification |> Ecto.Changeset.change(status: "sending") |> Repo.update!()

    assert :ok = perform_job(SendEmailWorker, %{"notification_id" => notification.id})

    refute_email_sent()
    assert Repo.get!(Notification, notification.id).status == "sending"
  end
end
