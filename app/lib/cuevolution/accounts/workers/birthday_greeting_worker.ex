defmodule Cuevolution.Accounts.Workers.BirthdayGreetingWorker do
  @moduledoc "Sends birthday greetings to players every morning at 11:00 EAT."

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Cuevolution.Accounts
  alias Cuevolution.Notifications

  @eat_offset_seconds 3 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    birthday = eat_today()
    birthday_key = Date.to_iso8601(birthday)

    Enum.each(Accounts.players_with_birthday_on(birthday), fn player ->
      dispatch_greeting(player, birthday_key)
    end)

    :ok
  end

  defp eat_today do
    DateTime.utc_now()
    |> DateTime.add(@eat_offset_seconds, :second)
    |> DateTime.to_date()
  end

  defp dispatch_greeting(player, birthday) do
    Notifications.dispatch(
      player,
      :birthday_greeting,
      %{},
      idempotency_key: "birthday-greeting:#{player.id}:#{birthday}"
    )
  rescue
    error ->
      require Logger

      Logger.error(
        "birthday_greeting dispatch failed for player #{player.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :ok
  end
end
