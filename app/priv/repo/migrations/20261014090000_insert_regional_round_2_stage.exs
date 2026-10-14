defmodule Cuevolution.Repo.Migrations.InsertRegionalRound2Stage do
  use Ecto.Migration

  @new_stage_name "Regional Round 2"

  def up do
    # Shift existing orders up by one, highest first, so no statement ever
    # collides with the unique index on `stages.order` mid-migration.
    execute(~s(UPDATE stages SET "order" = 6 WHERE name = 'Finals'))
    execute(~s(UPDATE stages SET "order" = 5 WHERE name = 'Circuit'))

    execute("""
    INSERT INTO stages (id, name, "order", inserted_at, updated_at)
    VALUES (gen_random_uuid(), '#{@new_stage_name}', 4, now(), now())
    """)
  end

  def down do
    execute("DELETE FROM stages WHERE name = '#{@new_stage_name}'")

    # Shift orders back down, lowest first, for the same collision-avoidance reason.
    execute(~s(UPDATE stages SET "order" = 4 WHERE name = 'Circuit'))
    execute(~s(UPDATE stages SET "order" = 5 WHERE name = 'Finals'))
  end
end
