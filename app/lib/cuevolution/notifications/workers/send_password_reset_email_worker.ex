defmodule Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker do
  @moduledoc """
  Sends a player's password-reset email (spec 011).

  Deliberately standalone rather than a `Notifications.dispatch/3` event
  type: that pipeline fans out by the player's stored `notification_preference`
  (a reset link must always go by email) and persists its payload into the
  admin-visible `Notification` log — a live reset credential must never sit
  in a table an admin can browse. No `Notification` row is created for this
  event type.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Mailer
  alias Cuevolution.Notifications.Emails
  alias Cuevolution.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"player_id" => player_id, "reset_url" => reset_url}}) do
    case Repo.get(Player, player_id) do
      %Player{} = player ->
        player
        |> Emails.reset_password_instructions(reset_url)
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
