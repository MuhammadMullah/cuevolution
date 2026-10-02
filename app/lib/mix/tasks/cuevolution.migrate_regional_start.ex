defmodule Mix.Tasks.Cuevolution.MigrateRegionalStart do
  @moduledoc """
  One-time: moves every existing female player's and team's current
  Grassroots `StageParticipation` to Regional, now that ladies and teams
  start there directly. Idempotent — only touches undrawn rows, so it's
  safe to re-run.

  In a production release (no Mix), use
  `Cuevolution.Release.migrate_regional_start/0` instead — both call
  `Cuevolution.Competitions.migrate_regional_start_enrollments/0`.
  """
  @shortdoc "Moves existing female/team Grassroots participants to Regional"

  use Mix.Task

  alias Cuevolution.Competitions

  def run(_args) do
    Mix.Task.run("app.start")

    %{moved: moved, skipped_drawn: skipped_drawn} =
      Competitions.migrate_regional_start_enrollments()

    Mix.shell().info(
      "Moved #{moved} participant(s) to Regional (skipped #{skipped_drawn} already drawn into a Grassroots group)."
    )
  end
end
