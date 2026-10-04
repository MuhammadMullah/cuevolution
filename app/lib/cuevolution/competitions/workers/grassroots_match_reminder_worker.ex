defmodule Cuevolution.Competitions.Workers.GrassrootsMatchReminderWorker do
  @moduledoc "Reminds eligible players to finish scheduled Grassroots fixtures before the deadline."

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Cuevolution.Competitions
  alias Cuevolution.Notifications

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    stage = Competitions.grassroots_stage()

    if reminder_active?(stage.completion_deadline) do
      deadline_date = stage.completion_deadline
      deadline = Date.to_iso8601(deadline_date)
      days_until_deadline = Date.diff(deadline_date, eat_today())

      dispatch_in_batches(deadline, days_until_deadline, 0)
    end

    :ok
  end

  defp reminder_active?(nil), do: false

  defp reminder_active?(deadline) do
    Date.compare(deadline, eat_today()) != :lt
  end

  defp eat_today do
    DateTime.utc_now() |> DateTime.add(3 * 60 * 60, :second) |> DateTime.to_date()
  end

  defp dispatch_reminder(player, deadline, reminder_kind) do
    Notifications.dispatch(
      player,
      :grassroots_match_reminder,
      %{deadline: deadline},
      idempotency_key: "grassroots-match-reminder:#{reminder_kind}:#{player.id}:#{deadline}"
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

  defp dispatch_in_batches(deadline, days_until_deadline, offset) do
    players = Competitions.players_with_grassroots_match_backlog(@batch_size, offset)

    case players do
      [] ->
        :ok

      players ->
        Enum.each(players, fn player ->
          dispatch_reminder(player, deadline, "initial")

          if days_until_deadline == 2 do
            dispatch_reminder(player, deadline, "48-hour")
          end
        end)

        dispatch_in_batches(deadline, days_until_deadline, offset + length(players))
    end
  end
end
