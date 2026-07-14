defmodule Cuevolution.Repo.Migrations.CreateStageCapacityConfigs do
  use Ecto.Migration

  def change do
    create table(:stage_capacity_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :capacity_limit, :integer, null: false
      add :current_count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:stage_capacity_configs, [:stage_id, :category])

    create constraint(:stage_capacity_configs, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    create constraint(:stage_capacity_configs, :capacity_limit_must_be_positive,
             check: "capacity_limit > 0"
           )

    create constraint(:stage_capacity_configs, :current_count_must_be_non_negative,
             check: "current_count >= 0"
           )

    # Seed default Circuit/Finals capacities (FR-005/FR-006). Grassroots and
    # Regional are open/uncapped (FR-002) and intentionally get no config
    # rows — `capacity_config/2` returning nil for those stages IS the
    # "open" signal `advance_to_stage/2` checks against.
    execute(
      """
      INSERT INTO stage_capacity_configs (id, stage_id, category, capacity_limit, current_count, inserted_at, updated_at)
      SELECT gen_random_uuid(), s.id, v.category, v.capacity_limit, 0, now(), now()
      FROM stages s
      JOIN (VALUES
        ('Circuit', 'male', 128),
        ('Circuit', 'female', 64),
        ('Circuit', 'team', 20),
        ('Finals', 'male', 64),
        ('Finals', 'female', 32),
        ('Finals', 'team', 8)
      ) AS v(stage_name, category, capacity_limit) ON v.stage_name = s.name
      """,
      "DELETE FROM stage_capacity_configs"
    )
  end
end
