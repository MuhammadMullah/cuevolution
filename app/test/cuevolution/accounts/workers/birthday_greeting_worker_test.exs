defmodule Cuevolution.Accounts.Workers.BirthdayGreetingWorkerTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Workers.BirthdayGreetingWorker
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo

  test "greets players whose birthday is today according to their preference" do
    today = eat_today()

    birthday_player =
      insert(:player,
        notification_preference: "both",
        date_of_birth: Date.new!(2000, today.month, today.day)
      )

    insert(:player, date_of_birth: Date.add(Date.new!(2000, today.month, today.day), -1))

    assert [^birthday_player] = Accounts.players_with_birthday_on(today)

    assert :ok = BirthdayGreetingWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 2

    assert Repo.get_by!(Notification,
             player_id: birthday_player.id,
             event_type: "birthday_greeting",
             channel: "email"
           ).payload == %{}

    assert :ok = BirthdayGreetingWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 2
  end

  test "does not greet anonymized players" do
    today = eat_today()

    player =
      insert(:player,
        date_of_birth: Date.new!(2000, today.month, today.day),
        anonymized_at: DateTime.utc_now()
      )

    assert player.id not in Enum.map(Accounts.players_with_birthday_on(today), & &1.id)
    assert :ok = BirthdayGreetingWorker.perform(%Oban.Job{})
    assert Repo.aggregate(Notification, :count, :id) == 0
  end

  # Mirrors the worker's own `eat_today/0` (EAT = UTC+3) — using
  # `Date.utc_today/0` here instead was flaky: in the last 3 hours of the
  # UTC day, EAT has already rolled over to the next date, so the worker
  # looks for a different "today" than the test set up and finds nobody.
  defp eat_today do
    DateTime.utc_now()
    |> DateTime.add(3 * 60 * 60, :second)
    |> DateTime.to_date()
  end
end
