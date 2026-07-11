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
    "team_assignment" => ~w(team_name captain_name)
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
  def dispatch(%Player{} = recipient, event_type, payload \\ %{}) when is_atom(event_type) do
    event_type = Atom.to_string(event_type)
    safe_payload = validate_payload!(event_type, payload)

    recipient
    |> channels_for()
    |> Enum.map(&enqueue(recipient, event_type, &1, safe_payload))
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

  defp enqueue(recipient, event_type, channel, payload) do
    {:ok, notification} =
      %Notification{}
      |> Notification.changeset(%{
        player_id: recipient.id,
        event_type: event_type,
        channel: channel,
        status: "pending",
        payload: payload,
        idempotency_key: Ecto.UUID.generate()
      })
      |> Repo.insert()

    worker = if channel == "email", do: SendEmailWorker, else: SendSmsWorker
    {:ok, _job} = %{"notification_id" => notification.id} |> worker.new() |> Oban.insert()

    Logger.info(
      "notification enqueued id=#{notification.id} channel=#{channel} " <>
        "event=#{event_type} player_id=#{recipient.id}"
    )

    notification
  end
end
