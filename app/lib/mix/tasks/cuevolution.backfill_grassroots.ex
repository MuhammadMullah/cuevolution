defmodule Mix.Tasks.Cuevolution.BackfillGrassroots do
  @moduledoc """
  Backfills a Grassroots `StageParticipation` for every player and team that
  predates auto-enrollment (spec 006). Idempotent — skips anyone who already
  has a participation for any stage, so it's safe to re-run.

  In a production release (no Mix), use `Cuevolution.Release.backfill_grassroots/0`
  instead — both call `Cuevolution.Competitions.backfill_grassroots_enrollments/0`.
  """
  @shortdoc "Backfills Grassroots StageParticipation for existing players/teams"

  use Mix.Task

  alias Cuevolution.Competitions

  def run(_args) do
    Mix.Task.run("app.start")

    %{players: {player_count, player_errors}, teams: {team_count, team_errors}} =
      Competitions.backfill_grassroots_enrollments()

    Mix.shell().info(
      "Enrolled #{player_count} player(s) and #{team_count} team(s) into Grassroots."
    )

    for {id, changeset} <- player_errors ++ team_errors do
      Mix.shell().error("Failed to enroll #{id}: #{inspect(changeset.errors)}")
    end
  end
end
