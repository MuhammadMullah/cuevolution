defmodule Cuevolution.Notifications.Notification do
  @moduledoc """
  A record of one attempted send to one recipient over one channel (spec
  002 Key Entities). `idempotency_key` is generated fresh per dispatched
  channel — see `Cuevolution.Notifications.dispatch/3` — and is what lets a
  crashed-and-retried job detect it's already claimed this specific send
  attempt rather than starting a second one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ~w(email sms)
  @statuses ~w(pending sending sent failed)

  schema "notifications" do
    field :event_type, :string
    field :channel, :string
    field :status, :string, default: "pending"
    field :payload, :map, default: %{}
    field :idempotency_key, :string
    field :error, :string
    field :retry_count, :integer, default: 0

    belongs_to :player, Cuevolution.Accounts.Player

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :player_id,
      :event_type,
      :channel,
      :status,
      :payload,
      :idempotency_key,
      :error,
      :retry_count
    ])
    |> validate_required([:player_id, :event_type, :channel, :idempotency_key])
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:idempotency_key)
    |> foreign_key_constraint(:player_id)
  end
end
