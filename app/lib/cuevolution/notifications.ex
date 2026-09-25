defmodule Cuevolution.Notifications do
  @moduledoc """
  The Notifications context is a single dispatch entry point that
  fans out to Email and/or SMS based on the recipient's stored preference,
  sends SMS only through the swappable `SmsAdapter` behaviour, and logs a
  `Notification` delivery-status row per channel for admin troubleshooting.

  Callers (`Accounts.register_player/1`, `Teams.add_player_to_roster/2`) call `dispatch/3` with an event
  type and a recipient — they never touch Swoosh, Oban, or an SMS provider
  directly (FR-008).
  """

  import Ecto.Query

  require Logger

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Notifications.Workers.SendEmailWorker
  alias Cuevolution.Notifications.Workers.SendSmsWorker
  alias Cuevolution.Repo

  # Explicit allowlist per event type dispatch/3 rejects any
  # payload key not listed here, so a caller can never leak another
  # person's contact info (e.g. an opponent's email/mobile) into a
  # notification's payload, not just the specific fields named in the
  # spec's edge cases, but anything not already known-safe.
  @allowed_payload_keys %{
    "registration_confirmation" => [],
    "fixture_assignment" => ~w(opponent_name venue date time),
    "team_assignment" => ~w(team_name captain_name),
    "team_invitation" => ~w(team_name captain_name),
    "team_player_left" => ~w(team_name player_name roster_count eligible),
    "player_location_updated" => ~w(region_name venue_name),
    "venue_deactivated" => ~w(venue_name suggested_venues),
    "draw_published" => ~w(fixtures)
  }

  @doc """
  Dispatches `event_type` to `recipient` via the channel(s) implied by
  their stored `notification_preference`. Creates one
  `Notification` row + enqueues one Oban job per channel — a failure on
  one channel (e.g. under "both") never blocks or rolls back the other.

  Raises `ArgumentError` if `payload` contains a key outside the allowlist
  for `event_type` — this is a contract violation by the calling code, not
  an expected runtime condition, so it isn't returned as an `{:error, _}`.

  Returns the list of created `Notification` structs (one per channel).
  """
  def dispatch(%Player{} = recipient, event_type, payload \\ %{}, opts \\ [])
      when is_atom(event_type) and is_list(opts) do
    event_type = Atom.to_string(event_type)
    safe_payload = validate_payload!(event_type, payload)

    recipient
    |> channels_for()
    |> Enum.map(&enqueue(recipient, event_type, &1, safe_payload, opts))
  end

  @doc """
  Re-queues up to `limit` `event_type`/`channel` notifications stuck in
  "failed" or "sending" (a crashed/restarted worker can leave a row
  claimed but never resolved) for another delivery attempt — resets each
  to "pending" and inserts a fresh Oban job.

  `limit` exists because a mass failure is often the *provider* throttling
  under a big burst (e.g. Gmail SMTP's ~500/day cap on a single account,
  see the 2026-09 draw-published incident) — re-queuing everything at once
  would immediately re-trigger the same throttling. Call this again for
  the next batch once you're confident there's send quota available,
  rather than draining the whole backlog in one shot.

  Returns `{requeued_count, still_failed_or_stuck_count}`.
  """
  def redrive_failed(event_type, channel, limit \\ 400) when channel in ["email", "sms"] do
    worker = if channel == "email", do: SendEmailWorker, else: SendSmsWorker

    candidates =
      Notification
      |> where([n], n.event_type == ^event_type and n.channel == ^channel)
      |> where([n], n.status in ["failed", "sending"])
      |> order_by([n], asc: n.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    Enum.each(candidates, fn notification ->
      notification |> Ecto.Changeset.change(status: "pending") |> Repo.update!()
      %{"notification_id" => notification.id} |> worker.new() |> Oban.insert!()
    end)

    remaining =
      Notification
      |> where([n], n.event_type == ^event_type and n.channel == ^channel)
      |> where([n], n.status in ["failed", "sending"])
      |> Repo.aggregate(:count)

    {length(candidates), remaining}
  end

  defp channels_for(%Player{notification_preference: "email"}), do: ["email"]
  defp channels_for(%Player{notification_preference: "sms"}), do: ["sms"]
  defp channels_for(%Player{notification_preference: "both"}), do: ["email", "sms"]

  defp validate_payload!(event_type, payload) do
    allowed = Map.fetch!(@allowed_payload_keys, event_type)
    string_payload = Map.new(payload, fn {k, v} -> {to_string(k), v} end)

    case Map.keys(string_payload) -- allowed do
      [] ->
        string_payload

      unexpected ->
        raise ArgumentError,
              "unsupported payload key(s) for #{event_type}: #{inspect(unexpected)} " <>
                "(allowed: #{inspect(allowed)})"
    end
  end

  defp enqueue(recipient, event_type, channel, payload, opts) do
    idempotency_key = Keyword.get(opts, :idempotency_key) || Ecto.UUID.generate()

    changeset =
      Notification.changeset(%Notification{}, %{
        player_id: recipient.id,
        event_type: event_type,
        channel: channel,
        status: "pending",
        payload: payload,
        idempotency_key: idempotency_key
      })

    case Repo.insert(changeset) do
      {:ok, notification} ->
        enqueue_delivery(notification, channel, event_type, recipient.id)
        notification

      {:error, changeset} ->
        if unique_idempotency_error?(changeset) do
          Repo.get_by!(Notification, idempotency_key: idempotency_key)
        else
          raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
        end
    end
  end

  defp enqueue_delivery(notification, channel, event_type, player_id) do
    worker = if channel == "email", do: SendEmailWorker, else: SendSmsWorker
    {:ok, _job} = %{"notification_id" => notification.id} |> worker.new() |> Oban.insert()

    Logger.info(
      "notification enqueued id=#{notification.id} channel=#{channel} " <>
        "event=#{event_type} player_id=#{player_id}"
    )
  end

  defp unique_idempotency_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:idempotency_key, {_message, metadata}} -> metadata[:constraint] == :unique
      _ -> false
    end)
  end
end
