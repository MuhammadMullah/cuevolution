defmodule Cuevolution.Repo.Migrations.RealignStageParticipationRegions do
  use Ecto.Migration

  @moduledoc """
  Backfills `stage_participations.region_id` from the player's current
  region.

  The column is a snapshot taken at enrollment and nothing refreshed it
  when a player's region was later corrected, while the admin Stages page
  filters on exactly that column — so those players dropped out of every
  region tab, present in `players` but unreachable in the console.
  `Competitions.realign_participation_regions/2` keeps the two in step from
  now on; this corrects the rows that already drifted.

  Participations dealt into a published draw are deliberately skipped:
  their group, fixtures and results all belong to the old region, so moving
  one across is a competition decision for an admin to make explicitly.
  Those stay visible via the Stages page's "All regions" filter.

  Category drift (a participation whose `category` disagrees with the
  player's `gender`) is *not* touched here. Entry stage is derived from
  gender — males enter at Grassroots, females at Regional — so correcting a
  category can imply moving someone between stages, which is likewise a
  competition decision rather than a data fix.
  """

  def up do
    execute("""
    UPDATE stage_participations AS sp
    SET region_id = p.region_id,
        updated_at = (NOW() AT TIME ZONE 'UTC')
    FROM players AS p
    WHERE p.id = sp.player_id
      AND sp.region_id IS DISTINCT FROM p.region_id
      AND NOT EXISTS (
        SELECT 1
        FROM group_memberships AS gm
        JOIN groups AS g ON g.id = gm.group_id
        WHERE gm.stage_participation_id = sp.id
          AND g.draw_id IS NOT NULL
      )
    """)
  end

  # The pre-backfill values were themselves the bug, and the column keeps no
  # history to restore them from, so this is deliberately one-way.
  def down, do: :ok
end
