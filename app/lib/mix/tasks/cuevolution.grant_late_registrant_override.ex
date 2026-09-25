defmodule Mix.Tasks.Cuevolution.GrantLateRegistrantOverride do
  @moduledoc """
  One-off: grants `:tournament_eligibility_override` to every player who
  registered between 21 and 25 September 2026 — the tournament committee's
  decision to admit these late registrants into this season's draw despite
  `Accounts.tournament_registration_cutoff/0`. Idempotent — safe to re-run.

  In a production release (no Mix), use
  `Cuevolution.Release.grant_late_registrant_override/0` instead — both call
  `Cuevolution.Accounts.grant_tournament_eligibility_override/2`.
  """
  @shortdoc "Grants the tournament eligibility override to 21-25 Sep 2026 registrants"

  use Mix.Task

  alias Cuevolution.Accounts

  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, usernames} =
      Accounts.grant_tournament_eligibility_override(
        ~N[2026-09-20 21:00:00],
        ~N[2026-09-25 21:00:00]
      )

    Mix.shell().info("Granted tournament_eligibility_override to #{length(usernames)} player(s):")
    Enum.each(usernames, &Mix.shell().info("  @#{&1}"))
  end
end
