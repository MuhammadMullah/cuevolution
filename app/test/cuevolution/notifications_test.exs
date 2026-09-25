defmodule Cuevolution.NotificationsTest do
  use Cuevolution.DataCase, async: true

  import ExUnit.CaptureLog

  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Notifications.Workers.SendEmailWorker
  alias Cuevolution.Notifications.Workers.SendSmsWorker

  describe "dispatch/3 channel fan-out (FR-001)" do
    test "preference \"email\" enqueues only an email notification" do
      player = insert(:player, notification_preference: "email")

      [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

      assert notification.channel == "email"
      assert notification.status == "pending"
      assert notification.event_type == "registration_confirmation"
      assert_enqueued(worker: SendEmailWorker, args: %{"notification_id" => notification.id})
      refute_enqueued(worker: SendSmsWorker)
    end

    test "logs enqueueing so a silent dispatch failure is traceable" do
      player = insert(:player, notification_preference: "sms")

      # capture_log's :level option can only restrict further, never loosen —
      # it can't see below config/test.exs's global `level: :warning`, so we
      # raise the primary level for this test only, then restore it.
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      log =
        capture_log(fn ->
          Notifications.dispatch(player, :registration_confirmation, %{})
        end)

      assert log =~ "notification enqueued"
      assert log =~ "channel=sms"
      assert log =~ "event=registration_confirmation"
      assert log =~ "player_id=#{player.id}"
    end

    test "preference \"sms\" enqueues only an sms notification" do
      player = insert(:player, notification_preference: "sms")

      [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

      assert notification.channel == "sms"
      assert_enqueued(worker: SendSmsWorker, args: %{"notification_id" => notification.id})
      refute_enqueued(worker: SendEmailWorker)
    end

    test "preference \"both\" enqueues one notification per channel" do
      player = insert(:player, notification_preference: "both")

      notifications = Notifications.dispatch(player, :registration_confirmation, %{})

      assert length(notifications) == 2
      assert notifications |> Enum.map(& &1.channel) |> Enum.sort() == ["email", "sms"]
      assert_enqueued(worker: SendEmailWorker)
      assert_enqueued(worker: SendSmsWorker)
    end
  end

  describe "dispatch/3 payload allowlisting (FR-010)" do
    test "raises for a payload key outside the event type's allowlist" do
      player = insert(:player)

      assert_raise ArgumentError, ~r/unsupported payload key/, fn ->
        Notifications.dispatch(player, :fixture_assignment, %{
          opponent_name: "Jane",
          venue: "Hall",
          date: "1 Jan",
          time: "10:00",
          opponent_email: "leak@example.com"
        })
      end
    end

    test "raises when the payload carries the opponent's mobile number" do
      player = insert(:player)

      assert_raise ArgumentError, fn ->
        Notifications.dispatch(player, :fixture_assignment, %{
          opponent_name: "Jane",
          venue: "Hall",
          date: "1 Jan",
          time: "10:00",
          opponent_mobile_number: "+254700000000"
        })
      end
    end

    test "accepts a payload using exactly the allowed keys" do
      player = insert(:player, notification_preference: "email")

      [notification] =
        Notifications.dispatch(player, :fixture_assignment, %{
          opponent_name: "Jane",
          venue: "Hall",
          date: "1 Jan",
          time: "10:00"
        })

      assert notification.payload["opponent_name"] == "Jane"
    end

    test "team_assignment rejects a payload key outside its allowlist" do
      player = insert(:player)

      assert_raise ArgumentError, fn ->
        Notifications.dispatch(player, :team_assignment, %{
          team_name: "The Sharks",
          captain_mobile_number: "+254700000000"
        })
      end
    end
  end

  test "reuses a deterministic idempotency key without creating a duplicate" do
    player = insert(:player, notification_preference: "email")
    opts = [idempotency_key: "draw_published:draw-1:#{player.id}"]

    [first] = Notifications.dispatch(player, :draw_published, %{fixtures: []}, opts)
    [second] = Notifications.dispatch(player, :draw_published, %{fixtures: []}, opts)

    assert second.id == first.id
    assert Repo.aggregate(Cuevolution.Notifications.Notification, :count, :id) == 1
  end

  test "two separate dispatches for the same player/event get distinct idempotency keys" do
    player = insert(:player, notification_preference: "email")

    [first] = Notifications.dispatch(player, :registration_confirmation, %{})
    [second] = Notifications.dispatch(player, :registration_confirmation, %{})

    refute first.idempotency_key == second.idempotency_key
  end

  describe "redrive_failed/3" do
    test "resets failed and stuck-sending notifications to pending and re-enqueues them" do
      player = insert(:player, notification_preference: "email")
      [failed] = Notifications.dispatch(player, :draw_published, %{fixtures: []})
      failed |> Ecto.Changeset.change(status: "failed", error: "boom") |> Repo.update!()

      other_player = insert(:player, notification_preference: "email")
      [stuck] = Notifications.dispatch(other_player, :draw_published, %{fixtures: []})
      stuck |> Ecto.Changeset.change(status: "sending") |> Repo.update!()

      assert {2, 0} = Notifications.redrive_failed("draw_published", "email")

      assert Repo.get!(Notification, failed.id).status == "pending"
      assert Repo.get!(Notification, stuck.id).status == "pending"
      assert_enqueued(worker: SendEmailWorker, args: %{"notification_id" => failed.id})
      assert_enqueued(worker: SendEmailWorker, args: %{"notification_id" => stuck.id})
    end

    test "leaves sent notifications untouched" do
      player = insert(:player, notification_preference: "email")
      [sent] = Notifications.dispatch(player, :draw_published, %{fixtures: []})
      sent |> Ecto.Changeset.change(status: "sent") |> Repo.update!()

      assert {0, 0} = Notifications.redrive_failed("draw_published", "email")
      assert Repo.get!(Notification, sent.id).status == "sent"
    end

    test "only re-queues up to the given limit, reporting how many are still left" do
      for _ <- 1..3 do
        player = insert(:player, notification_preference: "email")
        [notification] = Notifications.dispatch(player, :draw_published, %{fixtures: []})
        notification |> Ecto.Changeset.change(status: "failed") |> Repo.update!()
      end

      assert {1, 2} = Notifications.redrive_failed("draw_published", "email", 1)
    end

    test "scopes to the given event_type/channel, ignoring other failed notifications" do
      player = insert(:player, notification_preference: "both")
      [email, sms] = Notifications.dispatch(player, :draw_published, %{fixtures: []})
      email |> Ecto.Changeset.change(status: "failed") |> Repo.update!()
      sms |> Ecto.Changeset.change(status: "failed") |> Repo.update!()

      other_player = insert(:player, notification_preference: "email")
      [other_event] = Notifications.dispatch(other_player, :registration_confirmation, %{})
      other_event |> Ecto.Changeset.change(status: "failed") |> Repo.update!()

      assert {1, 0} = Notifications.redrive_failed("draw_published", "email")

      assert Repo.get!(Notification, email.id).status == "pending"
      assert Repo.get!(Notification, sms.id).status == "failed"
      assert Repo.get!(Notification, other_event.id).status == "failed"
    end
  end
end
