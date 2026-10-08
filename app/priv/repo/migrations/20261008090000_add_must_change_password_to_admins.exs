defmodule Cuevolution.Repo.Migrations.AddMustChangePasswordToAdmins do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :must_change_password, :boolean, default: false, null: false
    end
  end
end
