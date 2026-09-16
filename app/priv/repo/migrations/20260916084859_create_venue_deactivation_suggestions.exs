defmodule Cuevolution.Repo.Migrations.CreateVenueDeactivationSuggestions do
  use Ecto.Migration

  def change do
    create table(:venue_deactivation_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :venue_id, references(:venues, type: :binary_id, on_delete: :delete_all), null: false

      add :suggested_venue_id, references(:venues, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    # Lookup direction: "which venues were suggested when venue X was deactivated" —
    # driven by a player's (now-inactive) preferred_venue_id.
    create index(:venue_deactivation_suggestions, [:venue_id])

    create unique_index(:venue_deactivation_suggestions, [:venue_id, :suggested_venue_id])
  end
end
