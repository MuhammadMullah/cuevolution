defmodule Cuevolution.Competitions.Workers.GrassrootsMatchReminderWorker do
  @moduledoc "Reminds eligible players to finish scheduled Grassroots-round fixtures before each round's deadline."

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Cuevolution.Competitions
  alias Cuevolution.Notifications

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    [Competitions.grassroots_stage(), Competitions.grassroots_round_2_stage()]
    |> Enum.each(&maybe_dispatch_for_stage/1)

    :ok
  end

  defp maybe_dispatch_for_stage(stage) do
    if reminder_active?(stage.completion_deadline) do
      deadline = Date.to_iso8601(stage.completion_deadline)
      dispatch_in_batches(stage.id, deadline, 0)
    end
  end

  defp reminder_active?(nil), do: false

  defp reminder_active?(deadline) do
    Date.compare(deadline, eat_today()) != :lt
  end

  defp eat_today do
    DateTime.utc_now() |> DateTime.add(3 * 60 * 60, :second) |> DateTime.to_date()
  end

  defp dispatch_reminder(player, stage_id, deadline, reminder_kind) do
    Notifications.dispatch(
      player,
      :grassroots_match_reminder,
      %{deadline: deadline},
      idempotency_key:
        "grassroots-match-reminder:#{reminder_kind}:#{stage_id}:#{player.id}:#{deadline}"
    )
  rescue
    error ->
      require Logger

      Logger.error(
        "grassroots_match_reminder dispatch failed for player #{player.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :ok
  end

  defp dispatch_in_batches(stage_id, deadline, offset) do
    players = Competitions.players_with_grassroots_match_backlog(stage_id, @batch_size, offset)

    case players do
      [] ->
        :ok

      players ->
        Enum.each(players, &dispatch_reminder(&1, stage_id, deadline, "initial"))

        dispatch_in_batches(stage_id, deadline, offset + length(players))
    end
  end
end
