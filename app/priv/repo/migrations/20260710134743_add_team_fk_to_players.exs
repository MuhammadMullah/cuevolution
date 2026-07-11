defmodule Cuevolution.Repo.Migrations.AddTeamFkToPlayers do
  use Ecto.Migration

  def change do
    # players.team_id was created as a plain column back in the players
    # migration because `teams` didn't exist yet (the two tables forward
    # -reference each other: teams.captain_id -> players, players.team_id ->
    # teams). Now that `teams` exists, add the real constraint.
    alter table(:players) do
      modify :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end
  end
end
