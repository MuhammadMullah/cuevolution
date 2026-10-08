defmodule Cuevolution.Seeds.VenueRepresentativesTest do
  use Cuevolution.DataCase, async: true

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Seeds.VenueRepresentatives
  alias Cuevolution.Venues.Venue

  defp central_region, do: Repo.get_by!(Region, name: "Central")

  describe "run_central_region_direct/0" do
    test "creates all 22 reps directly, active, with the shared temporary password" do
      summary = VenueRepresentatives.run_central_region_direct()

      assert summary.created == 22
      assert summary.overridden == 0
      assert summary.skipped_active == 0
      assert summary.failed == 0

      admin = Repo.get_by!(Admin, email: "loyfordsomi@gmail.com")
      assert admin.role == "venue_representative"
      assert admin.must_change_password
      refute Admin.pending?(admin)
      assert {:ok, _} = Accounts.authenticate_admin(admin.email, "VenueRep@26")
    end

    test "reuses an existing venue instead of creating a duplicate" do
      region = central_region()
      existing = insert(:venue, name: "Aquatic (Meru)", region_id: region.id)

      VenueRepresentatives.run_central_region_direct()

      admin = Repo.get_by!(Admin, email: "loyfordsomi@gmail.com")
      assert admin.venue_id == existing.id

      assert Repo.aggregate(
               from(v in Venue, where: v.region_id == ^region.id and v.name == "Aquatic (Meru)"),
               :count
             ) == 1
    end

    test "creates a fresh venue for a representative with no existing match" do
      region = central_region()

      VenueRepresentatives.run_central_region_direct()

      admin = Repo.get_by!(Admin, email: "harrisonmugambi05@gmail.com")
      venue = Repo.get!(Venue, admin.venue_id)
      assert venue.name == "Gee Spot"
      assert venue.region_id == region.id
    end

    test "running it twice leaves everyone active the second time (idempotent)" do
      VenueRepresentatives.run_central_region_direct()
      second_run = VenueRepresentatives.run_central_region_direct()

      assert second_run.created == 0
      assert second_run.overridden == 0
      assert second_run.skipped_active == 22
    end

    test "overrides a pending admin that already exists under one of these emails" do
      other_venue = insert(:venue)

      pending =
        insert(:admin,
          hashed_password: nil,
          role: "venue_representative",
          venue_id: other_venue.id,
          email: "loyfordsomi@gmail.com"
        )

      summary = VenueRepresentatives.run_central_region_direct()

      assert summary.created == 21
      assert summary.overridden == 1

      updated = Repo.get!(Admin, pending.id)
      refute updated.venue_id == other_venue.id
      assert updated.must_change_password
      refute Admin.pending?(updated)
    end

    test "leaves an already-active admin under one of these emails completely untouched" do
      active =
        insert(:admin,
          role: "venue_representative",
          venue_id: insert(:venue).id,
          email: "loyfordsomi@gmail.com",
          hashed_password: Bcrypt.hash_pwd_salt("TheirOwnChoice@1")
        )

      summary = VenueRepresentatives.run_central_region_direct()

      assert summary.created == 21
      assert summary.skipped_active == 1

      unchanged = Repo.get!(Admin, active.id)
      assert unchanged.hashed_password == active.hashed_password
      assert unchanged.venue_id == active.venue_id
      refute unchanged.must_change_password
    end
  end
end
