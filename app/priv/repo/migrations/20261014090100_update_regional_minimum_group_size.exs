defmodule Cuevolution.Repo.Migrations.UpdateRegionalMinimumGroupSize do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE stage_group_configs
    SET minimum_group_size = 7
    WHERE category IN ('male', 'female')
      AND stage_id = (SELECT id FROM stages WHERE name = 'Regional')
    """)
  end

  def down do
    execute("""
    UPDATE stage_group_configs
    SET minimum_group_size = 6
    WHERE category IN ('male', 'female')
      AND stage_id = (SELECT id FROM stages WHERE name = 'Regional')
    """)
  end
end
