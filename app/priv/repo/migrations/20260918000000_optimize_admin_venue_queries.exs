defmodule Cuevolution.Repo.Migrations.OptimizeAdminVenueQueries do
  use Ecto.Migration

  def change do
    create index(:players, [:region_id, :other_venue_name],
             name: :players_custom_venue_submissions_index,
             where: "other_venue_name IS NOT NULL AND other_venue_name <> ''"
           )
  end
end
