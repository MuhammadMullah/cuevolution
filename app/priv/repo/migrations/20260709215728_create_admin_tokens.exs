defmodule Cuevolution.Repo.Migrations.CreateAdminTokens do
  use Ecto.Migration

  def change do
    create table(:admin_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :admin_id, references(:admins, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false)
    end

    create index(:admin_tokens, [:admin_id])
    create unique_index(:admin_tokens, [:context, :token])
  end
end
