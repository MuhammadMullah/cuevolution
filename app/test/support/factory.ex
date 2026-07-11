defmodule Cuevolution.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Cuevolution.Repo

  import Ecto.Query

  alias Cuevolution.Accounts.{Admin, Player, Region}
  alias Cuevolution.Teams.Team
  alias Cuevolution.Venues.Venue

  def region_factory do
    regions = Cuevolution.Repo.all(from r in Region, order_by: r.slug)
    index = sequence(:region_cycle, & &1)
    Enum.at(regions, rem(index, length(regions)))
  end

  def admin_factory do
    %Admin{
      email: sequence(:email, &"admin-#{&1}@cuevolution.test"),
      hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass")
    }
  end

  def player_factory do
    region = build(:region)

    %Player{
      first_name: sequence(:first_name, &"Player#{&1}"),
      last_name: "Test",
      date_of_birth: Date.add(Date.utc_today(), -365 * 20),
      gender: Enum.random(["male", "female"]),
      email: sequence(:email, &"player-#{&1}@cuevolution.test"),
      mobile_number:
        sequence(:mobile_number, &"+2547#{String.pad_leading(to_string(&1), 8, "0")}"),
      location: "Nairobi",
      username: sequence(:username, &"player#{&1}"),
      notification_preference: "email",
      hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass"),
      region_id: region.id
    }
  end

  def venue_factory do
    region = build(:region)

    %Venue{
      name: sequence(:venue_name, &"Venue #{&1}"),
      active: true,
      region_id: region.id
    }
  end

  # Builds a team with a real, persisted captain. Note the captain's own
  # `team_id` isn't back-filled here — that bidirectional link is a job for
  # `Teams.create_team/2` (captain + roster consistency is exactly what that
  # function's Multi guarantees). Tests that need a fully roster-consistent
  # team should go through `Teams.create_team/2`, not this shortcut.
  def team_factory do
    captain = insert(:player)

    %Team{
      name: sequence(:team_name, &"Team #{&1}"),
      region_id: captain.region_id,
      captain_id: captain.id
    }
  end
end
