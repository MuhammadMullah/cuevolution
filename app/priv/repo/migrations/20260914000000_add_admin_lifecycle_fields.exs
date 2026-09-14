defmodule Cuevolution.Repo.Migrations.AddAdminLifecycleFields do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :suspended_at, :utc_datetime
      add :removed_at, :utc_datetime
    end
  end
end
