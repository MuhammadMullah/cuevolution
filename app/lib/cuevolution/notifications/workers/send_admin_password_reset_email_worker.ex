defmodule Cuevolution.Notifications.Workers.SendAdminPasswordResetEmailWorker do
  @moduledoc """
  Sends an admin's password-reset email. Standalone rather than routed
  through `Notifications.dispatch/3`, matching `SendPasswordResetEmailWorker`
  — a live reset credential must never sit in the admin-visible
  `Notification` log.
  """
  use Oban.Worker, queue: :notifications_critical, max_attempts: 5

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Mailer
  alias Cuevolution.Notifications.Emails
  alias Cuevolution.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"admin_id" => admin_id, "reset_url" => reset_url}}) do
    case Repo.get(Admin, admin_id) do
      %Admin{} = admin ->
        admin
        |> Emails.admin_reset_password_instructions(reset_url)
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
