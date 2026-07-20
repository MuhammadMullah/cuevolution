defmodule Cuevolution.Repo.Migrations.CreateCuevoPointsEntries do
  use Ecto.Migration

  def change do
    create table(:cuevo_points_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :participant_id,
          references(:stage_participations, type: :binary_id, on_delete: :restrict),
          null: false

      add :match_result_id, references(:match_results, type: :binary_id, on_delete: :restrict),
        null: false

      add :match_frame_id, references(:match_frames, type: :binary_id, on_delete: :restrict)

      add :points, :integer, null: false
      add :prior_value, :map

      add :recorded_by_admin_id, references(:admins, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps()
    end

    # SUM-aggregation hot path (standings_for_category/1, points_total/1) —
    # index deliberately, not incidentally.
    create index(:cuevo_points_entries, [:participant_id])
    create index(:cuevo_points_entries, [:match_result_id])
    create index(:cuevo_points_entries, [:match_frame_id])
  end
end
