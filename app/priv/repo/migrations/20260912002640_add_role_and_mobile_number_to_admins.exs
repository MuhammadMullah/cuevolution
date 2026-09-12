defmodule Cuevolution.Repo.Migrations.AddRoleAndMobileNumberToAdmins do
  use Ecto.Migration

  def up do
    alter table(:admins) do
      add :role, :string
      add :mobile_number, :string
      modify :hashed_password, :string, null: true
    end

    execute("UPDATE admins SET role = 'super_admin' WHERE role IS NULL")

    alter table(:admins) do
      modify :role, :string, null: false
    end

    create unique_index(:admins, [:mobile_number])
  end

  def down do
    drop unique_index(:admins, [:mobile_number])

    alter table(:admins) do
      modify :hashed_password, :string, null: false
      remove :mobile_number
      remove :role
    end
  end
end
