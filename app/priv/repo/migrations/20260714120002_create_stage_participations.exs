defmodule Cuevolution.Repo.Migrations.CreateStageParticipations do
  use Ecto.Migration

  def change do
    create table(:stage_participations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all)
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all)
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :joined_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:stage_participations, [:stage_id, :region_id, :category])
    create index(:stage_participations, [:player_id])
    create index(:stage_participations, [:team_id])

    create constraint(:stage_participations, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    # Exactly one of player_id/team_id must be set — a Stage Participation is
    # a record of a PLAYER'S OR TEAM'S current stage, never both.
    create constraint(:stage_participations, :exactly_one_participant_type,
             check: """
             (player_id IS NOT NULL AND team_id IS NULL) OR
             (player_id IS NULL AND team_id IS NOT NULL)
             """
           )
  end
end
