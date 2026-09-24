defmodule Cuevolution.Repo.Migrations.AllowSystemDoubleWalkovers do
  use Ecto.Migration

  def change do
    alter table(:match_results) do
      modify :winner_participation_id, :binary_id, from: {:binary_id, null: false}, null: true

      modify :recorded_by_admin_id, :binary_id, from: {:binary_id, null: false}, null: true
    end
  end
end
