defmodule Cuevolution.Repo.Migrations.AddPreApprovalRedrawCount do
  use Ecto.Migration

  def change do
    alter table(:draws) do
      add :redraw_count, :integer, null: false, default: 0
    end

    create constraint(:draws, :draw_redraw_count_valid,
             check: "redraw_count >= 0 AND redraw_count <= 3"
           )
  end
end
