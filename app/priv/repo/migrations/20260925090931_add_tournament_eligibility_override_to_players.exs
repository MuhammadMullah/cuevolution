defmodule Cuevolution.Repo.Migrations.AddTournamentEligibilityOverrideToPlayers do
  use Ecto.Migration

  # Grants a specific player an exception to `Accounts.tournament_registration_cutoff/0`
  # (2026-09-20 21:00 UTC) — set on players the tournament committee decided, after
  # the fact, to admit into this season's draw despite registering late. Deliberately
  # per-player rather than moving the cutoff itself, which stays in force for anyone
  # who registers late from here on.
  def change do
    alter table(:players) do
      add :tournament_eligibility_override, :boolean, null: false, default: false
    end
  end
end
