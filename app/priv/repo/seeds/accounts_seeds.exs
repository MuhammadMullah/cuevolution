defmodule Cuevolution.Seeds.Accounts do
  @moduledoc """
  Seeds the default admin account and a batch of sample players.
  Idempotent — safe to re-run. Depends on `Cuevolution.Seeds.Venues` having
  already run (players need a venue to select at registration).
  """

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.{Admin, Player, Region}
  alias Cuevolution.Repo
  alias Cuevolution.Venues.Venue

  @admin_email "admin@cuevolution.test"
  @admin_password "Seed1!Admin"
  @player_count 40
  @player_username_prefix "seedplayer"

  def run do
    seed_admin()
    seed_players()
  end

  defp seed_admin do
    case Repo.get_by(Admin, email: @admin_email) do
      nil ->
        {:ok, _admin} =
          %Admin{}
          |> Admin.registration_changeset(%{email: @admin_email, password: @admin_password})
          |> Repo.insert()

        IO.puts("Seeded admin: #{@admin_email} / #{@admin_password}")

      _admin ->
        IO.puts("Admin already seeded: #{@admin_email}")
    end
  end

  defp seed_players do
    already_seeded =
      Repo.aggregate(
        from(p in Player, where: like(p.username, ^"#{@player_username_prefix}%")),
        :count
      )

    if already_seeded >= @player_count do
      IO.puts("Players already seeded (#{already_seeded}).")
    else
      regions = Repo.all(Region)

      Enum.each((already_seeded + 1)..@player_count, fn n ->
        seed_player(n, regions)
      end)

      IO.puts("Seeded players #{already_seeded + 1}..#{@player_count}.")
    end
  end

  defp seed_player(n, regions) do
    region = Enum.at(regions, rem(n, length(regions)))
    venue = Repo.one(from v in Venue, where: v.region_id == ^region.id, limit: 1)

    attrs = %{
      "first_name" => "Seed",
      "last_name" => "Player#{n}",
      "date_of_birth" => "2000-01-01",
      "gender" => if(rem(n, 2) == 0, do: "male", else: "female"),
      "email" => "#{@player_username_prefix}#{n}@cuevolution.test",
      "mobile_number" => "07#{String.pad_leading(Integer.to_string(n), 8, "0")}",
      "location" => region.name,
      "country" => "KE",
      "username" => "#{@player_username_prefix}#{n}",
      "notification_preference" => "email",
      "region_id" => region.id,
      "password" => "Valid1!Pass"
    }

    attrs =
      if venue,
        do: Map.put(attrs, "preferred_venue_id", venue.id),
        else: Map.put(attrs, "other_venue_name", "Local Hall")

    case Accounts.register_player(attrs) do
      {:ok, _player} -> :ok
      {:error, changeset} -> IO.warn("Failed to seed player #{n}: #{inspect(changeset.errors)}")
    end
  end
end

Cuevolution.Seeds.Accounts.run()
