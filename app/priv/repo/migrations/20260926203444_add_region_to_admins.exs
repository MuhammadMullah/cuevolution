defmodule Cuevolution.Repo.Migrations.AddRegionToAdmins do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :region_id, references(:regions, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:admins, [:region_id])
  end
end
