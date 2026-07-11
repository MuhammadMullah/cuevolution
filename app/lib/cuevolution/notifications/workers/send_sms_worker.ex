defmodule Cuevolution.Notifications.Workers.SendSmsWorker do
  @moduledoc """
  Sends the SMS for a `Notification` row (channel == "sms") via the
  configured `Cuevolution.Notifications.SmsAdapter` and records the
  outcome. See `Cuevolution.Notifications.Workers.Support` for the
  crash-safe claim step (spec 002 FR-009).
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Cuevolution.Notifications.SmsMessages
  alias Cuevolution.Notifications.Workers.Support

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Support.claim(id) do
      {:ok, notification} -> send_and_record(notification)
      :already_claimed -> :ok
    end
  end

  defp send_and_record(notification) do
    adapter = Application.get_env(:cuevolution, :sms_adapter)
    body = build_body(notification)

    case adapter.send(notification.player.mobile_number, body) do
      {:ok, _meta} ->
        Support.mark_sent(notification)
        :ok

      {:error, reason} ->
        Support.mark_failed(notification, reason)
        {:error, reason}
    end
  end

  defp build_body(%{event_type: "registration_confirmation", player: player}) do
    SmsMessages.registration_confirmation(player)
  end

  defp build_body(%{event_type: "fixture_assignment", player: player, payload: payload}) do
    SmsMessages.fixture_assignment(player, Support.atomize_payload(payload))
  end

  defp build_body(%{event_type: "team_assignment", player: player, payload: payload}) do
    SmsMessages.team_assignment(player, Support.atomize_payload(payload))
  end
end
