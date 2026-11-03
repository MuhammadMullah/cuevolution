defmodule Cuevolution.Repo.Migrations.AllowNationalTeamDraw do
  use Ecto.Migration

  # A draw has always belonged to exactly one venue or one region. The Circuit
  # team event is national — 20 teams, 2 groups, one draw for the country — so
  # it belongs to neither.
  #
  # The allowance is deliberately narrow: only a `team` draw may be
  # scope-less. A men's or ladies' draw is always venue- or region-scoped, so
  # for those a missing scope is still a bug and still rejected.
  def up do
    drop constraint(:draws, :draws_scope_present)

    create constraint(:draws, :draws_scope_present,
             check: """
             (venue_id IS NOT NULL AND region_id IS NULL)
             OR (venue_id IS NULL AND region_id IS NOT NULL)
             OR (venue_id IS NULL AND region_id IS NULL AND category = 'team')
             """
           )
  end

  def down do
    execute "DELETE FROM draws WHERE venue_id IS NULL AND region_id IS NULL"

    drop constraint(:draws, :draws_scope_present)

    create constraint(:draws, :draws_scope_present,
             check: """
             (venue_id IS NOT NULL AND region_id IS NULL)
             OR (venue_id IS NULL AND region_id IS NOT NULL)
             """
           )
  end
end
