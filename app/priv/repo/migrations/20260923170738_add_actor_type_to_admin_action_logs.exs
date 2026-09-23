defmodule Cuevolution.Repo.Migrations.AddActorTypeToAdminActionLogs do
  use Ecto.Migration

  def change do
    alter table(:admin_action_logs) do
      modify :admin_id, :binary_id, null: true
      add :actor_type, :string, null: false, default: "admin"
    end

    create constraint(:admin_action_logs, :admin_action_log_actor_valid,
             check:
               "(actor_type = 'admin' AND admin_id IS NOT NULL) OR (actor_type = 'system' AND admin_id IS NULL)"
           )
  end
end
