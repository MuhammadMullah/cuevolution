defmodule Cuevolution.Notifications.Workers.SendEmailWorker do
  @moduledoc """
  Sends the email for a `Notification` row (channel == "email") and
  records the outcome. See `Cuevolution.Notifications.Workers.Support` for
  the crash-safe claim step (spec 002 FR-009).
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Cuevolution.Mailer
  alias Cuevolution.Notifications.Emails
  alias Cuevolution.Notifications.Workers.Support

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Support.claim(id) do
      {:ok, notification} -> send_and_record(notification)
      :already_claimed -> :ok
    end
  end

  defp send_and_record(notification) do
    case Mailer.deliver(build_email(notification)) do
      {:ok, _meta} ->
        Support.mark_sent(notification)
        :ok

      {:error, reason} ->
        Support.mark_failed(notification, reason)
        {:error, reason}
    end
  end

  defp build_email(%{event_type: "registration_confirmation", player: player}) do
    Emails.registration_confirmation(player)
  end

  defp build_email(%{event_type: "fixture_assignment", player: player, payload: payload}) do
    Emails.fixture_assignment(player, Support.atomize_payload(payload))
  end

  defp build_email(%{event_type: "team_assignment", player: player, payload: payload}) do
    Emails.team_assignment(player, Support.atomize_payload(payload))
  end
end
