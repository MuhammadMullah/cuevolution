defmodule Cuevolution.Repo.Migrations.AddTieBreakersToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :tie_breakers, {:array, :string}, null: false, default: []
    end
  end
end
