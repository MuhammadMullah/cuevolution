defmodule Cuevolution.Repo.Migrations.CreateDraws do
  use Ecto.Migration

  def change do
    create table(:draws, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :state, :string, null: false, default: "draft"
      add :random_seed, :string
      add :group_count_override, :integer
      add :formula_group_count, :integer, null: false

      timestamps()
    end

    create index(:draws, [:stage_id, :venue_id, :category])
    create index(:draws, [:state])

    create constraint(:draws, :draw_state_valid,
             check: "state IN ('draft', 'previewed', 'approved', 'published')"
           )

    create constraint(:draws, :draw_category_valid, check: "category IN ('male', 'female')")

    create constraint(:draws, :draw_group_counts_positive,
             check:
               "formula_group_count > 0 AND (group_count_override IS NULL OR group_count_override > 0)"
           )
  end
end
