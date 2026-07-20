defmodule Cuevolution.Repo.Migrations.CreateMatchResults do
  use Ecto.Migration

  def change do
    create table(:match_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :fixture_id, references(:fixtures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :winner_participation_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :score, :map
      add :prior_value, :map

      add :recorded_by_admin_id, references(:admins, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps()
    end

    # FR-007 dup guard: only one result per fixture, enforced at the DB
    # level, not just in the changeset.
    create unique_index(:match_results, [:fixture_id])
    create index(:match_results, [:winner_participation_id])
    create index(:match_results, [:recorded_by_admin_id])

    # Wire up the forward reference left plain in the fixtures migration
    # (same deferred-FK pattern as add_team_fk_to_players.exs).
    alter table(:fixtures) do
      modify :result_id, references(:match_results, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end
  end
end
