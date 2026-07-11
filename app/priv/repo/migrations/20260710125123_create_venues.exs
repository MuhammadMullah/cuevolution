defmodule Cuevolution.Repo.Migrations.CreateVenues do
  use Ecto.Migration

  def change do
    create table(:venues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :active, :boolean, null: false, default: true

      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false

      timestamps()
    end

    # The hot query is "active venues for region X" (Venues.list_active_for_region/1).
    create index(:venues, [:region_id, :active])

    # Case-insensitive uniqueness scoped to active venues only: a deactivated
    # venue's name doesn't block creating a new active one with the same name.
    create unique_index(:venues, [:region_id, "lower(name)"],
             name: :venues_region_lower_name_active_index,
             where: "active = true"
           )
  end
end
