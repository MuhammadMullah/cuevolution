defmodule Cuevolution.Repo.Migrations.AddMatchLocationToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :match_region_id, references(:regions, type: :binary_id, on_delete: :restrict)
      add :match_venue_id, references(:venues, type: :binary_id, on_delete: :restrict)
    end

    create index(:teams, [:match_region_id])
    create index(:teams, [:match_venue_id])
  end
end
