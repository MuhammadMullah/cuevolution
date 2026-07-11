defmodule Cuevolution.Repo.Migrations.AddPreferredVenueToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      # Nullable and on_delete: :nilify_all — deactivating (not deleting) a
      # venue is the only supported removal path (spec 004 FR-004), so this
      # nilify is a belt-and-suspenders guard, not the normal flow.
      add :preferred_venue_id, references(:venues, type: :binary_id, on_delete: :nilify_all)

      # Free-text venue name when the player picks "Other" instead of a
      # preloaded venue (spec 004 FR-003 / Key Entities: "Custom Venue Entry").
      add :other_venue_name, :string
    end

    create index(:players, [:preferred_venue_id])
  end
end
