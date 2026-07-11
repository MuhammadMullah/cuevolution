defmodule Cuevolution.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :captain_id, references(:players, type: :binary_id, on_delete: :restrict), null: false

      # Nullable: set once the team's first Match Result exists (spec 008,
      # Context 5, not yet built) — the FR-008 roster freeze itself is
      # deferred until then (see T058/T061 in tasks.md).
      add :roster_locked_at, :utc_datetime

      timestamps()
    end

    create index(:teams, [:region_id])
    create index(:teams, [:captain_id])
  end
end
