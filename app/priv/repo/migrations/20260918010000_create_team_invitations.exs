defmodule Cuevolution.Repo.Migrations.CreateTeamInvitations do
  use Ecto.Migration

  def change do
    create table(:team_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false

      add :invited_by_id,
          references(:players, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :responded_at, :utc_datetime

      timestamps()
    end

    create index(:team_invitations, [:player_id])
    create index(:team_invitations, [:team_id])
    create index(:team_invitations, [:status])

    create unique_index(:team_invitations, [:team_id, :player_id],
             where: "status = 'pending'",
             name: :team_invitations_one_pending_per_team_player
           )

    create constraint(:team_invitations, :status_must_be_valid,
             check: "status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')"
           )
  end
end
