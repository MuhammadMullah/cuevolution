defmodule Mix.Tasks.Cuevolution.BackfillGrassroots do
  @moduledoc """
  Backfills a Grassroots `StageParticipation` for every player and team that
  predates auto-enrollment (spec 006). Idempotent — skips anyone who already
  has a participation for any stage, so it's safe to re-run.
  """
  @shortdoc "Backfills Grassroots StageParticipation for existing players/teams"

  use Mix.Task

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team

  def run(_args) do
    Mix.Task.run("app.start")

    {player_count, player_errors} = backfill_players()
    {team_count, team_errors} = backfill_teams()

    Mix.shell().info(
      "Enrolled #{player_count} player(s) and #{team_count} team(s) into Grassroots."
    )

    for {id, changeset} <- player_errors ++ team_errors do
      Mix.shell().error("Failed to enroll #{id}: #{inspect(changeset.errors)}")
    end
  end

  defp backfill_players do
    enrolled_ids = participation_ids(:player_id)

    Player
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(enrolled_ids, &1.id))
    |> Enum.reduce({0, []}, fn player, {count, errors} ->
      case player |> Competitions.enroll_player_in_grassroots_changeset() |> Repo.insert() do
        {:ok, _} -> {count + 1, errors}
        {:error, changeset} -> {count, [{player.id, changeset} | errors]}
      end
    end)
  end

  defp backfill_teams do
    enrolled_ids = participation_ids(:team_id)

    Team
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(enrolled_ids, &1.id))
    |> Enum.reduce({0, []}, fn team, {count, errors} ->
      case team |> Competitions.enroll_team_in_grassroots_changeset() |> Repo.insert() do
        {:ok, _} -> {count + 1, errors}
        {:error, changeset} -> {count, [{team.id, changeset} | errors]}
      end
    end)
  end

  defp participation_ids(field) do
    StageParticipation
    |> where([sp], not is_nil(field(sp, ^field)))
    |> select([sp], field(sp, ^field))
    |> Repo.all()
    |> MapSet.new()
  end
end
