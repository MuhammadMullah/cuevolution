defmodule Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker do
  @moduledoc """
  Sends the account-setup email to a newly invited admin. Standalone rather
  than routed through `Notifications.dispatch/3`, matching
  `SendPasswordResetEmailWorker` — a live setup credential must always go by
  email and must never sit in the admin-visible `Notification` log.

  Delivery outcome is still tracked, just on the admin record itself
  (`invite_email_status`) rather than a `Notification` row, so the inviting
  super admin can see a stuck/failed invite instead of it silently vanishing
  after the final retry — see `CuevolutionWeb.AdminManagementLive`.
  """
  use Oban.Worker, queue: :notifications_critical, max_attempts: 5

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Mailer
  alias Cuevolution.Notifications.Emails
  alias Cuevolution.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"admin_id" => admin_id, "setup_url" => setup_url},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case Repo.get(Admin, admin_id) do
      %Admin{} = admin -> deliver(admin, setup_url, attempt, max_attempts)
      nil -> :ok
    end
  end

  defp deliver(admin, setup_url, attempt, max_attempts) do
    admin
    |> Emails.admin_invitation(setup_url)
    |> Mailer.deliver()
    |> case do
      {:ok, _meta} ->
        mark_email_sent(admin)
        :ok

      {:error, reason} ->
        if attempt >= max_attempts, do: mark_email_failed(admin)
        {:error, reason}
    end
  end

  defp mark_email_sent(admin) do
    admin
    |> Ecto.Changeset.change(invite_email_status: "sent", invite_email_failed_at: nil)
    |> Repo.update!()
  end

  defp mark_email_failed(admin) do
    admin
    |> Ecto.Changeset.change(
      invite_email_status: "failed",
      invite_email_failed_at: DateTime.utc_now(:second)
    )
    |> Repo.update!()
  end
end
