defmodule Cuevolution.Seeds.RegionalCoordinatorsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Repo
  alias Cuevolution.Seeds.RegionalCoordinators

  describe "run_direct/0" do
    test "creates the coordinator directly, active, with the shared temporary password" do
      summary = RegionalCoordinators.run_direct()

      assert summary.created == 1
      assert summary.overridden == 0
      assert summary.skipped_active == 0
      assert summary.failed == 0

      admin = Repo.get_by!(Admin, email: "kipronoismael0@gmail.com")
      assert admin.role == "regional_coordinator"
      assert admin.must_change_password
      refute Admin.pending?(admin)
      assert {:ok, _} = Accounts.authenticate_admin(admin.email, "RegionCoord@26")
    end

    test "assigns the correct region" do
      region = Repo.get_by!(Cuevolution.Accounts.Region, name: "South Rift")

      RegionalCoordinators.run_direct()

      admin = Repo.get_by!(Admin, email: "kipronoismael0@gmail.com")
      assert admin.region_id == region.id
    end

    test "overrides a pending admin that already exists under this email instead of duplicating" do
      pending =
        insert(:admin,
          hashed_password: nil,
          role: "regional_coordinator",
          email: "kipronoismael0@gmail.com"
        )

      summary = RegionalCoordinators.run_direct()

      assert summary.created == 0
      assert summary.overridden == 1

      updated = Repo.get!(Admin, pending.id)
      assert updated.must_change_password
      refute Admin.pending?(updated)
      assert Repo.aggregate(Admin, :count) == 1
    end

    test "leaves an already-active admin under this email completely untouched" do
      active =
        insert(:admin,
          role: "regional_coordinator",
          email: "kipronoismael0@gmail.com",
          hashed_password: Bcrypt.hash_pwd_salt("TheirOwnChoice@1")
        )

      summary = RegionalCoordinators.run_direct()

      assert summary.created == 0
      assert summary.skipped_active == 1

      unchanged = Repo.get!(Admin, active.id)
      assert unchanged.hashed_password == active.hashed_password
      refute unchanged.must_change_password
    end

    test "running it twice leaves the coordinator active the second time (idempotent)" do
      RegionalCoordinators.run_direct()
      second_run = RegionalCoordinators.run_direct()

      assert second_run.created == 0
      assert second_run.overridden == 0
      assert second_run.skipped_active == 1
    end
  end
end
