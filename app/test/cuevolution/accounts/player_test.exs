defmodule Cuevolution.Accounts.PlayerTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.Player

  defp valid_attrs(overrides \\ %{}) do
    region = build(:region)

    Map.merge(
      %{
        first_name: "Jane",
        last_name: "Doe",
        date_of_birth: Date.add(Date.utc_today(), -365 * 20),
        gender: "female",
        email: "jane-#{System.unique_integer([:positive])}@example.com",
        mobile_number: "0712345678",
        location: "Nairobi",
        username: "janedoe#{System.unique_integer([:positive])}",
        notification_preference: "email",
        region_id: region.id,
        other_venue_name: "Test Venue",
        password: "Valid1!Pass"
      },
      overrides
    )
  end

  describe "registration_changeset/2" do
    test "valid attrs produce a valid changeset with a hashed password" do
      changeset = Player.registration_changeset(%Player{}, valid_attrs())

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :hashed_password)
      refute Ecto.Changeset.get_change(changeset, :password)
    end

    test "rejects an age under 18" do
      attrs = valid_attrs(%{date_of_birth: Date.add(Date.utc_today(), -365 * 17)})
      changeset = Player.registration_changeset(%Player{}, attrs)

      refute changeset.valid?
      assert "must be at least 18 years old" in errors_on(changeset).date_of_birth
    end

    test "accepts exactly 18 years old (inclusive boundary)" do
      today = Date.utc_today()
      exactly_18_dob = %{today | year: today.year - 18}

      changeset =
        Player.registration_changeset(%Player{}, valid_attrs(%{date_of_birth: exactly_18_dob}))

      assert changeset.valid?
    end

    test "rejects a duplicate username case-insensitively at the DB level" do
      insert(:player, username: "JohnD")

      changeset = Player.registration_changeset(%Player{}, valid_attrs(%{username: "johnd"}))
      assert changeset.valid?

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).username
    end

    test "rejects a duplicate email case-insensitively at the DB level" do
      insert(:player, email: "Taken@Example.com")

      changeset =
        Player.registration_changeset(%Player{}, valid_attrs(%{email: "taken@example.com"}))

      assert changeset.valid?

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "defaults country to Kenya (KE) when not given" do
      changeset = Player.registration_changeset(%Player{}, valid_attrs())

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :country) == "KE"
    end

    test "rejects a country that isn't a 2-letter ISO code" do
      changeset = Player.registration_changeset(%Player{}, valid_attrs(%{country: "Kenya"}))

      refute changeset.valid?
      assert "must be a 2-letter ISO country code (e.g. KE)" in errors_on(changeset).country
    end

    test "normalizes the mobile number against the given country, not just the Kenya default" do
      changeset =
        Player.registration_changeset(
          %Player{},
          valid_attrs(%{country: "US", mobile_number: "202-456-1111"})
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :mobile_number) == "+12024561111"
    end

    test "requires the core fields" do
      changeset = Player.registration_changeset(%Player{}, %{})

      refute changeset.valid?

      for field <- [
            :first_name,
            :last_name,
            :date_of_birth,
            :gender,
            :email,
            :mobile_number,
            :location,
            :username,
            :notification_preference,
            :region_id,
            :preferred_venue_id,
            :password
          ] do
        assert errors_on(changeset)[field], "expected an error on #{field}"
      end
    end

    test "rejects registration with neither a preferred venue nor an 'Other' venue name" do
      changeset =
        Player.registration_changeset(%Player{}, valid_attrs(%{other_venue_name: nil}))

      refute changeset.valid?

      assert "select a venue or specify one under \"Other\"" in errors_on(changeset).preferred_venue_id
    end

    test "rejects registration with both a preferred venue and an 'Other' venue name" do
      venue = insert(:venue)

      changeset =
        Player.registration_changeset(
          %Player{},
          valid_attrs(%{preferred_venue_id: venue.id, other_venue_name: "Some Venue"})
        )

      refute changeset.valid?

      assert "choose either a venue or \"Other\", not both" in errors_on(changeset).preferred_venue_id
    end

    test "accepts registration with only a preferred venue selected" do
      venue = insert(:venue)

      changeset =
        Player.registration_changeset(
          %Player{},
          valid_attrs(%{preferred_venue_id: venue.id, other_venue_name: nil})
        )

      assert changeset.valid?
    end
  end
end
