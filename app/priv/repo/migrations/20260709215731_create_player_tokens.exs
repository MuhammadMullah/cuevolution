defmodule Cuevolution.Repo.Migrations.CreatePlayerTokens do
  use Ecto.Migration

  def change do
    create table(:player_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false)
    end

    create index(:player_tokens, [:player_id])
    create unique_index(:player_tokens, [:context, :token])
  end
end
