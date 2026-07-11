defmodule Cuevolution.Notifications.Workers.Support do
  @moduledoc """
  Shared claim/status-update logic for the email and SMS send workers —
  the atomic claim step is what makes a crashed-and-retried job safe (spec
  002 FR-009/SC-005): a crash between a successful provider call and the
  status write leaves the row stuck at "sending", which the claim query
  below refuses to reclaim, so a retry never calls the provider a second
  time for the same attempt.
  """
  import Ecto.Query
  require Logger

  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo

  @doc """
  Atomically transitions the notification from "pending"/"failed" to
  "sending". Returns `{:ok, notification}` (preloaded with `:player`) if
  this call won the claim, or `:already_claimed` if another attempt
  already has it (in flight or done) — callers should treat that as a
  no-op success rather than an error.
  """
  def claim(notification_id) do
    query =
      from(n in Notification,
        where: n.id == ^notification_id and n.status in ["pending", "failed"]
      )

    case Repo.update_all(query, set: [status: "sending"]) do
      {1, _} -> {:ok, Notification |> Repo.get!(notification_id) |> Repo.preload(:player)}
      {0, _} -> :already_claimed
    end
  end

  def mark_sent(notification) do
    Logger.info(
      "notification sent id=#{notification.id} channel=#{notification.channel} " <>
        "event=#{notification.event_type} player_id=#{notification.player_id}"
    )

    notification |> Ecto.Changeset.change(status: "sent", error: nil) |> Repo.update!()
  end

  def mark_failed(notification, reason) do
    Logger.error(
      "notification failed id=#{notification.id} channel=#{notification.channel} " <>
        "event=#{notification.event_type} player_id=#{notification.player_id} " <>
        "reason=#{inspect(reason)}"
    )

    notification
    |> Ecto.Changeset.change(
      status: "failed",
      error: inspect(reason),
      retry_count: notification.retry_count + 1
    )
    |> Repo.update!()
  end

  @doc "String-keyed payload (as stored/JSON-round-tripped) back to the atom keys the template builders expect."
  def atomize_payload(payload) do
    Map.new(payload, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
