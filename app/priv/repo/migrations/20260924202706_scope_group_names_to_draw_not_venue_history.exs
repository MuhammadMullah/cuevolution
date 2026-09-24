defmodule Cuevolution.Repo.Migrations.ScopeGroupNamesToDrawNotVenueHistory do
  use Ecto.Migration

  # `groups_venue_scoped_unique_index` was `(stage_id, venue_id, category,
  # name)`, unique across every group ever created at that venue+category —
  # not just the current draw. Redraws never delete the superseded draw's
  # groups (kept for audit history), so a fresh redraw's "Group A" collided
  # with the old draw's still-existing "Group A" and got silently renamed
  # "Group A (2)", "Group A (3)", ... on every subsequent redraw — a
  # confusing, meaningless suffix admins had no way to interpret.
  #
  # Split into two indexes: auto-dealt groups (`draw_id` set) are unique
  # only within their own draw, so every fresh deal/redraw starts clean at
  # "Group A" again; manually-created groups (`draw_id` is always null —
  # Team category, Regional) keep the original venue-wide uniqueness so two
  # manually-named groups still can't collide.
  def change do
    drop unique_index(:groups, [:stage_id, :venue_id, :category, :name],
           name: :groups_venue_scoped_unique_index
         )

    create unique_index(:groups, [:draw_id, :name],
             where: "draw_id IS NOT NULL",
             name: :groups_draw_scoped_unique_index
           )

    create unique_index(:groups, [:stage_id, :venue_id, :category, :name],
             where: "venue_id IS NOT NULL AND draw_id IS NULL",
             name: :groups_venue_scoped_unique_index
           )
  end
end
