defmodule Cuevolution.Repo.Migrations.CreateMatchFrames do
  use Ecto.Migration

  def change do
    create table(:match_frames, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_result_id, references(:match_results, type: :binary_id, on_delete: :delete_all),
        null: false

      add :home_player_id, references(:players, type: :binary_id, on_delete: :restrict),
        null: false

      add :away_player_id, references(:players, type: :binary_id, on_delete: :restrict),
        null: false

      add :winner_player_id, references(:players, type: :binary_id, on_delete: :restrict),
        null: false

      add :sequence, :integer, null: false

      timestamps()
    end

    create index(:match_frames, [:match_result_id])
    create unique_index(:match_frames, [:match_result_id, :sequence])
    create index(:match_frames, [:home_player_id])
    create index(:match_frames, [:away_player_id])

    create constraint(:match_frames, :winner_must_be_home_or_away,
             check: "winner_player_id = home_player_id OR winner_player_id = away_player_id"
           )

    create constraint(:match_frames, :sequence_must_be_positive, check: "sequence > 0")
  end
end
