defmodule Cuevolution.Repo.Migrations.RenameTournamentManagerRole do
  use Ecto.Migration

  def up do
    execute("UPDATE admins SET role = 'tournament_director' WHERE role = 'tournament_manager'")
  end

  def down do
    execute("UPDATE admins SET role = 'tournament_manager' WHERE role = 'tournament_director'")
  end
end
