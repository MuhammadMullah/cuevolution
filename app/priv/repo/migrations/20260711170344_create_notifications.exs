defmodule Cuevolution.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :channel, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :payload, :map, null: false, default: %{}
      add :idempotency_key, :string, null: false
      add :error, :string
      add :retry_count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:notifications, [:idempotency_key])
    create index(:notifications, [:player_id])
    create index(:notifications, [:status])

    create constraint(:notifications, :channel_must_be_valid,
             check: "channel IN ('email', 'sms')"
           )

    create constraint(:notifications, :status_must_be_valid,
             check: "status IN ('pending', 'sending', 'sent', 'failed')"
           )
  end
end
