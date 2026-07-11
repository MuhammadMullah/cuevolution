defmodule Cuevolution.Accounts.ConcurrentRegistrationTest do
  # Spawns real processes that hit the same DB connection concurrently, so
  # this needs the sandbox in shared mode (DataCase enables that automatically
  # for async: false).
  use Cuevolution.DataCase, async: false

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player

  defp attrs(overrides) do
    region = build(:region)

    Map.merge(
      %{
        first_name: "Concurrent",
        last_name: "Player",
        date_of_birth: Date.add(Date.utc_today(), -365 * 20),
        gender: "female",
        location: "Nairobi",
        notification_preference: "email",
        region_id: region.id,
        other_venue_name: "Test Venue",
        password: "Valid1!Pass"
      },
      overrides
    )
  end

  test "N concurrent registrations with genuinely unique data all succeed (NFR-1.1)" do
    attrs_list =
      for i <- 1..20,
          do:
            attrs(%{
              username: "concurrent#{i}",
              email: "concurrent#{i}@example.com",
              mobile_number: "07000#{String.pad_leading(to_string(i), 5, "0")}"
            })

    results =
      attrs_list
      |> Task.async_stream(&Accounts.register_player/1, max_concurrency: 10, timeout: 5_000)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %Player{}}, &1))
    assert Repo.aggregate(Player, :count) == 20
  end

  test "concurrent registrations racing for the same username: exactly one succeeds" do
    attrs_list =
      for i <- 1..10,
          do:
            attrs(%{
              username: "sameusername",
              email: "racer#{i}@example.com",
              mobile_number: "07001#{String.pad_leading(to_string(i), 5, "0")}"
            })

    results =
      attrs_list
      |> Task.async_stream(&Accounts.register_player/1, max_concurrency: 10, timeout: 5_000)
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &match?({:ok, %Player{}}, &1))
    failures = Enum.count(results, &match?({:error, %Ecto.Changeset{}}, &1))

    assert successes == 1
    assert failures == 9
    assert Repo.aggregate(from(p in Player, where: p.username == "sameusername"), :count) == 1
  end

  test "concurrent registrations racing for the same email: exactly one succeeds" do
    attrs_list =
      for i <- 1..10,
          do:
            attrs(%{
              username: "emailracer#{i}",
              email: "same@example.com",
              mobile_number: "07002#{String.pad_leading(to_string(i), 5, "0")}"
            })

    results =
      attrs_list
      |> Task.async_stream(&Accounts.register_player/1, max_concurrency: 10, timeout: 5_000)
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &match?({:ok, %Player{}}, &1))
    failures = Enum.count(results, &match?({:error, %Ecto.Changeset{}}, &1))

    assert successes == 1
    assert failures == 9
  end
end
