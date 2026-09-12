defmodule Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker do
  @moduledoc """
  Sends the account-setup email to a newly invited admin. Standalone rather
  than routed through `Notifications.dispatch/3`, matching
  `SendPasswordResetEmailWorker` — a live setup credential must always go by
  email and must never sit in the admin-visible `Notification` log.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Mailer
  alias Cuevolution.Notifications.Emails
  alias Cuevolution.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"admin_id" => admin_id, "setup_url" => setup_url}}) do
    case Repo.get(Admin, admin_id) do
      %Admin{} = admin ->
        admin
        |> Emails.admin_invitation(setup_url)
        |> Mailer.deliver()
        |> case do
          {:ok, _meta} -> :ok
          {:error, reason} -> {:error, reason}
        end

      nil ->
        :ok
    end
  end
end
