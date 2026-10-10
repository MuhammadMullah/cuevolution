defmodule Cuevolution.Repo.Migrations.InsertGrassrootsRound2Stage do
  use Ecto.Migration

  @new_stage_name "Grassroots Round 2"

  def up do
    # Shift existing orders up by one, highest first, so no statement ever
    # collides with the unique index on `stages.order` mid-migration.
    execute(~s(UPDATE stages SET "order" = 5 WHERE name = 'Finals'))
    execute(~s(UPDATE stages SET "order" = 4 WHERE name = 'Circuit'))
    execute(~s(UPDATE stages SET "order" = 3 WHERE name = 'Regional'))

    execute("""
    INSERT INTO stages (id, name, "order", inserted_at, updated_at)
    VALUES (gen_random_uuid(), '#{@new_stage_name}', 2, now(), now())
    """)

    # Reuse Round 1's current (possibly admin-tuned) group-size/advancer
    # settings for Round 2, per category — same rules, same format.
    execute("""
    INSERT INTO stage_group_configs (
      id, stage_id, category, group_size, advancer_count, target_group_size,
      minimum_group_size, minimum_entrants, extra_qualifier_count, inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), new_stage.id, c.category, c.group_size, c.advancer_count,
      c.target_group_size, c.minimum_group_size, c.minimum_entrants,
      c.extra_qualifier_count, now(), now()
    FROM stage_group_configs c
    JOIN stages old_stage ON old_stage.id = c.stage_id AND old_stage.name = 'Grassroots'
    JOIN stages new_stage ON new_stage.name = '#{@new_stage_name}'
    """)
  end

  def down do
    execute("""
    DELETE FROM stage_group_configs
    WHERE stage_id = (SELECT id FROM stages WHERE name = '#{@new_stage_name}')
    """)

    execute("DELETE FROM stages WHERE name = '#{@new_stage_name}'")

    # Shift orders back down, lowest first, for the same collision-avoidance reason.
    execute(~s(UPDATE stages SET "order" = 2 WHERE name = 'Regional'))
    execute(~s(UPDATE stages SET "order" = 3 WHERE name = 'Circuit'))
    execute(~s(UPDATE stages SET "order" = 4 WHERE name = 'Finals'))
  end
end
