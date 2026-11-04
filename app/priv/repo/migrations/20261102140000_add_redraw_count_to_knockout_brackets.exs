defmodule Cuevolution.Repo.Migrations.AddRedrawCountToKnockoutBrackets do
  use Ecto.Migration

  @moduledoc """
  Gives the Circuit draw the same three-re-deals-before-approval allowance the
  round-robin stages already have (`draws.redraw_count`, spec 012).

  The Circuit has no `draws` row — a national knockout fits neither the
  venue-scoped nor region-scoped shape that table requires, and has no groups
  to count — so the allowance is tracked on the bracket itself. The bracket row
  therefore outlives a re-deal: only its rounds and fixtures are rebuilt, which
  is what lets the count survive.
  """

  def change do
    alter table(:knockout_brackets) do
      add :redraw_count, :integer, null: false, default: 0
    end

    create constraint(:knockout_brackets, :knockout_redraw_count_valid,
             check: "redraw_count >= 0 AND redraw_count <= 3"
           )
  end
end
