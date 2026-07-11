defmodule Cuevolution.Repo.Migrations.AddUniqueIndexToPlayersMobileNumber do
  use Ecto.Migration

  def change do
    create unique_index(:players, [:mobile_number])
  end
end
