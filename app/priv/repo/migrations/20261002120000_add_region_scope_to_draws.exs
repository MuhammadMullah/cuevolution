defmodule Cuevolution.Repo.Migrations.AddRegionScopeToDraws do
  use Ecto.Migration

  def change do
    alter table(:draws) do
      modify :venue_id, :binary_id, null: true
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict)
    end

    create index(:draws, [:stage_id, :region_id, :category])

    drop constraint(:draws, :draw_category_valid)

    create constraint(:draws, :draw_category_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    create constraint(:draws, :draws_scope_present,
             check: """
             (venue_id IS NOT NULL AND region_id IS NULL) OR
             (venue_id IS NULL AND region_id IS NOT NULL)
             """
           )
  end
end
