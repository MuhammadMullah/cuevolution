defmodule Cuevolution.Repo.Migrations.AllowNationalGroups do
  use Ecto.Migration

  # The Circuit team event is played as round-robin groups (spec 014): 20
  # teams in 2 groups of 10, one season-long round robin. Unlike Grassroots
  # (venue-scoped) and Regional (region-scoped), those groups are national —
  # the two groups are the whole country — so a group can now exist with no
  # region.
  #
  # Uniqueness for a drawn group is already covered by
  # `groups_draw_scoped_unique_index` on `(draw_id, name)`. The index added
  # here covers a hand-made national group, mirroring what
  # `groups_venue_scoped_unique_index` does for venues.
  def up do
    alter table(:groups) do
      modify :region_id, :binary_id, null: true
    end

    create unique_index(
             :groups,
             [:stage_id, :category, :name],
             where: "region_id IS NULL AND venue_id IS NULL AND draw_id IS NULL",
             name: :groups_national_unique_index
           )
  end

  def down do
    drop index(:groups, [:stage_id, :category, :name], name: :groups_national_unique_index)

    # Only reversible while no national group exists; a region is required
    # again, so any row without one would fail the constraint.
    execute "DELETE FROM group_memberships WHERE group_id IN (SELECT id FROM groups WHERE region_id IS NULL)"

    execute "DELETE FROM fixtures WHERE round_id IN (SELECT id FROM rounds WHERE group_id IN (SELECT id FROM groups WHERE region_id IS NULL))"

    execute "DELETE FROM rounds WHERE group_id IN (SELECT id FROM groups WHERE region_id IS NULL)"
    execute "DELETE FROM groups WHERE region_id IS NULL"

    alter table(:groups) do
      modify :region_id, :binary_id, null: false
    end
  end
end
