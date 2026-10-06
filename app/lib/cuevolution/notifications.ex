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
    "draw_published" => ~w(fixtures),
    "grassroots_match_reminder" => ~w(deadline),
    "grassroots_deadline_apology" => ~w(deadline),
    "birthday_greeting" => []
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
  Batched counterpart to `dispatch/3` for events with many recipients at
  once (a published draw's fixtures, a venue-wide relocation) — same
  channel-routing/payload-allowlist/idempotency semantics, but writes all
  `Notification` rows and enqueues all delivery jobs in two `insert_all`
  calls total instead of two round trips per recipient per channel. A
  draw can fan out to hundreds of recipients; looping `dispatch/3` over
  them pins a DB connection for that many sequential inserts, the same
  shape of bug fixed in the draw/fixture-generation pipeline.

  `entries` is a list of `{recipient, payload, idempotency_key}` tuples
  sharing one `event_type`. As in `dispatch/3`'s `idempotency_key` option,
  the channel is appended to each entry's key so a "both"-preference
  recipient gets one distinct key per channel.

  Unlike `dispatch/3`, a recipient already notified under a given
  idempotency key is silently skipped at the DB level (no row, no job) —
  there's no per-recipient return value to resolve back to, since callers
  of this function act on the batch as a whole, not on one recipient's
  result.

  Raises `ArgumentError` on the same payload-allowlist violation as
  `dispatch/3`, applied per entry.
  """
  def dispatch_many(entries, event_type) when is_atom(event_type) and is_list(entries) do
    event_type = Atom.to_string(event_type)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      for {recipient, payload, idempotency_key} <- entries,
          safe_payload = validate_payload!(event_type, payload),
          channel <- channels_for(recipient) do
        %{
          id: Ecto.UUID.generate(),
          player_id: recipient.id,
          event_type: event_type,
          channel: channel,
          status: "pending",
          payload: safe_payload,
          idempotency_key: "#{idempotency_key}:#{channel}",
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, inserted} =
      Repo.insert_all(Notification, rows,
        on_conflict: :nothing,
        conflict_target: :idempotency_key,
        returning: [:id, :channel]
      )

    inserted
    |> Enum.map(fn notification ->
      worker = if notification.channel == "email", do: SendEmailWorker, else: SendSmsWorker
      worker.new(%{"notification_id" => notification.id})
    end)
    |> Oban.insert_all()

    Logger.info(
      "notifications batch-enqueued event=#{event_type} requested=#{length(rows)} created=#{length(inserted)}"
    )

    :ok
  end

  @doc """
  Re-queues up to `limit` `event_type`/`channel` notifications stuck in
  "failed" or "sending" (a crashed/restarted worker can leave a row
  claimed but never resolved) for another delivery attempt — resets each
  to "pending" and inserts a fresh Oban job.

  `limit` exists because a mass failure is often the *provider* throttling
  under a big burst (see the 2026-09 draw-published incident) — re-queuing everything at once
  would immediately re-trigger the same throttling. Call this again for
  the next batch once you're confident there's send quota available,
  rather than draining the whole backlog in one shot.

  Returns `{requeued_count, still_failed_or_stuck_count}`.
  """
  def redrive_failed(event_type, channel, limit \\ 400) when channel in ["email", "sms"] do
    worker = if channel == "email", do: SendEmailWorker, else: SendSmsWorker

    candidate_ids =
      Notification
      |> where([n], n.event_type == ^event_type and n.channel == ^channel)
      |> where([n], n.status in ["failed", "sending"])
      |> order_by([n], asc: n.inserted_at)
      |> limit(^limit)
      |> select([n], n.id)
      |> Repo.all()

    Notification
    |> where([n], n.id in ^candidate_ids)
    |> Repo.update_all(set: [status: "pending"])

    candidate_ids
    |> Enum.map(&worker.new(%{"notification_id" => &1}))
    |> Oban.insert_all()

    remaining =
      Notification
      |> where([n], n.event_type == ^event_type and n.channel == ^channel)
      |> where([n], n.status in ["failed", "sending"])
      |> Repo.aggregate(:count)

    {length(candidate_ids), remaining}
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
    idempotency_key =
      case Keyword.get(opts, :idempotency_key) do
        nil -> Ecto.UUID.generate()
        base_key -> "#{base_key}:#{channel}"
      end

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
