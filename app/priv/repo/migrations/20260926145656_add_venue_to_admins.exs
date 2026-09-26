defmodule Cuevolution.Repo.Migrations.AddVenueToAdmins do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :venue_id, references(:venues, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:admins, [:venue_id])
  end
end
