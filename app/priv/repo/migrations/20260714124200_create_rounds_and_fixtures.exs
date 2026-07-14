defmodule Cuevolution.Repo.Migrations.CreateRoundsAndFixtures do
  use Ecto.Migration

  def change do
    create table(:rounds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      # Nullable: knockout-stage rounds may be tied to a knockout_bracket
      # rather than a group directly in a later phase; group-stage rounds
      # (Grassroots/Regional) always set this.
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false

      timestamps()
    end

    create index(:rounds, [:stage_id])
    create index(:rounds, [:group_id])

    create table(:fixtures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :round_id, references(:rounds, type: :binary_id, on_delete: :delete_all), null: false

      add :participant_a_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :participant_b_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict), null: false
      add :scheduled_at, :utc_datetime, null: false

      # Forward reference: match_results doesn't exist until the next plan.
      # Plain binary_id column now; the real FK constraint is added via
      # `modify ... references(...), from: :binary_id` in that migration —
      # same deferred-FK pattern used for players.team_id -> teams.
      add :result_id, :binary_id

      timestamps()
    end

    create index(:fixtures, [:round_id])
    create index(:fixtures, [:participant_a_id])
    create index(:fixtures, [:participant_b_id])
    create index(:fixtures, [:venue_id])
    create unique_index(:fixtures, [:result_id])

    # FR-007: reject a duplicate pairing within the same round, regardless
    # of which participant is entered as "a" vs "b". least()/greatest() on
    # uuid work fine in Postgres (uuid has a default btree operator class).
    create unique_index(
             :fixtures,
             [
               :round_id,
               "least(participant_a_id, participant_b_id)",
               "greatest(participant_a_id, participant_b_id)"
             ],
             name: :fixtures_round_participants_unique_index
           )

    create constraint(:fixtures, :participants_must_differ,
             check: "participant_a_id <> participant_b_id"
           )
  end
end
