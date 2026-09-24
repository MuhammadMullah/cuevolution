defmodule Cuevolution.Repo.Migrations.AddStatusAndMatchIdToFixtures do
  use Ecto.Migration

  def change do
    alter table(:fixtures) do
      add :status, :string, null: false, default: "scheduled"
      add :match_id, :string
      add :walkover_kind, :string
      modify :scheduled_at, :utc_datetime, null: true, from: {:utc_datetime, null: false}
      modify :venue_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    create index(:fixtures, [:status])
    create unique_index(:fixtures, [:match_id], where: "match_id IS NOT NULL")

    create constraint(:fixtures, :fixture_status_valid,
             check:
               "status IN ('scheduled', 'live', 'completed', 'verified', 'walkover', 'postponed', 'abandoned')"
           )

    create constraint(:fixtures, :walkover_kind_valid,
             check: "walkover_kind IS NULL OR walkover_kind IN ('single', 'double')"
           )
  end
end
