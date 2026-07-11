defmodule Cuevolution.Repo.Migrations.CreateAdminActionLogs do
  use Ecto.Migration

  def change do
    create table(:admin_action_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:admins, type: :binary_id, on_delete: :restrict), null: false
      add :action_type, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :prior_value, :map
      add :new_value, :map

      timestamps(updated_at: false)
    end

    create index(:admin_action_logs, [:admin_id])
    create index(:admin_action_logs, [:inserted_at])
    create index(:admin_action_logs, [:entity_type, :entity_id])
  end
end
