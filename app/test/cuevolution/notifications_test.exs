defmodule Cuevolution.NotificationsTest do
  use Cuevolution.DataCase, async: true

  import ExUnit.CaptureLog

  alias Cuevolution.Notifications
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

  test "two separate dispatches for the same player/event get distinct idempotency keys" do
    player = insert(:player, notification_preference: "email")

    [first] = Notifications.dispatch(player, :registration_confirmation, %{})
    [second] = Notifications.dispatch(player, :registration_confirmation, %{})

    refute first.idempotency_key == second.idempotency_key
  end
end
