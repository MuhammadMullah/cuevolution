defmodule Cuevolution.Repo.Migrations.AddDrawIdToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :draw_id, references(:draws, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:groups, [:draw_id])
  end
end
