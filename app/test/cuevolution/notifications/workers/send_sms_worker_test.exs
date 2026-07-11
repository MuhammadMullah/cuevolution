defmodule Cuevolution.Notifications.Workers.SendSmsWorkerTest do
  use Cuevolution.DataCase, async: true

  import ExUnit.CaptureLog
  import Mox

  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Notifications.SmsAdapter.SmsAdapterMock
  alias Cuevolution.Notifications.Workers.SendSmsWorker
  alias Cuevolution.Repo

  setup :verify_on_exit!

  test "sends the registration-confirmation sms via the configured adapter" do
    player = insert(:player, notification_preference: "sms")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    expect(SmsAdapterMock, :send, fn mobile_number, body ->
      assert mobile_number == player.mobile_number
      assert body =~ player.first_name
      {:ok, %{}}
    end)

    assert :ok = perform_job(SendSmsWorker, %{"notification_id" => notification.id})

    assert Repo.get!(Notification, notification.id).status == "sent"
  end

  test "sends the fixture-assignment sms with the fixture details" do
    player = insert(:player, notification_preference: "sms")

    payload = %{
      opponent_name: "Jane Doe",
      venue: "Westlands Cue Club",
      date: "12 Jul",
      time: "3:00 PM"
    }

    [notification] = Notifications.dispatch(player, :fixture_assignment, payload)

    expect(SmsAdapterMock, :send, fn _mobile_number, body ->
      assert body =~ "Jane Doe"
      assert body =~ "Westlands Cue Club"
      {:ok, %{}}
    end)

    assert :ok = perform_job(SendSmsWorker, %{"notification_id" => notification.id})
  end

  test "marks the notification failed when the adapter errors, and never crashes the job" do
    player = insert(:player, notification_preference: "sms")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    expect(SmsAdapterMock, :send, fn _mobile_number, _body -> {:error, :timeout} end)

    assert {:error, :timeout} =
             perform_job(SendSmsWorker, %{"notification_id" => notification.id})

    updated = Repo.get!(Notification, notification.id)
    assert updated.status == "failed"
    assert updated.error =~ "timeout"
    assert updated.retry_count == 1
  end

  test "logs a successful send" do
    player = insert(:player, notification_preference: "sms")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    expect(SmsAdapterMock, :send, fn _mobile_number, _body -> {:ok, %{}} end)

    # capture_log's :level option can only restrict further, never loosen —
    # it can't see below config/test.exs's global `level: :warning`, so we
    # raise the primary level for this test only, then restore it.
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)

    log =
      capture_log(fn ->
        assert :ok = perform_job(SendSmsWorker, %{"notification_id" => notification.id})
      end)

    assert log =~ "notification sent"
    assert log =~ "id=#{notification.id}"
    assert log =~ "channel=sms"
  end

  test "logs the failure reason so an adapter/provider error is visible without querying the DB" do
    player = insert(:player, notification_preference: "sms")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})

    expect(SmsAdapterMock, :send, fn _mobile_number, _body ->
      {:error, {:provider_rejected, "InvalidSenderId"}}
    end)

    log =
      capture_log(fn ->
        assert {:error, {:provider_rejected, "InvalidSenderId"}} =
                 perform_job(SendSmsWorker, %{"notification_id" => notification.id})
      end)

    assert log =~ "notification failed"
    assert log =~ "id=#{notification.id}"
    assert log =~ "InvalidSenderId"
  end

  test "a notification already claimed by another attempt is skipped, not re-sent (FR-009/SC-005)" do
    player = insert(:player, notification_preference: "sms")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})
    notification |> Ecto.Changeset.change(status: "sending") |> Repo.update!()

    # Zero calls expected — if the worker called the adapter anyway,
    # verify_on_exit! fails this test.
    expect(SmsAdapterMock, :send, 0, fn _mobile_number, _body -> {:ok, %{}} end)

    assert :ok = perform_job(SendSmsWorker, %{"notification_id" => notification.id})

    assert Repo.get!(Notification, notification.id).status == "sending"
  end
end
