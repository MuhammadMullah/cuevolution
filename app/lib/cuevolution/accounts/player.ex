defmodule Cuevolution.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cuevolution.Accounts.PasswordValidator
  alias Cuevolution.Accounts.PhoneNumber
  alias Cuevolution.Venues

  @genders ~w(male female)
  @notification_preferences ~w(email sms both)
  @minimum_age 18

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :first_name, :string
    field :last_name, :string
    field :date_of_birth, :date
    field :gender, :string
    field :email, :string
    field :mobile_number, :string
    field :profile_picture_path, :string
    field :location, :string
    field :country, :string, default: "KE"
    # Free-text venue name, used only when no preloaded venue is selected
    # (spec 004 FR-003 "Custom Venue Entry").
    field :other_venue_name, :string
    field :username, :string
    field :notification_preference, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :current_password, :string, virtual: true
    field :anonymized_at, :utc_datetime

    belongs_to :region, Cuevolution.Accounts.Region
    belongs_to :preferred_venue, Cuevolution.Venues.Venue
    belongs_to :team, Cuevolution.Teams.Team

    timestamps()
  end

  @doc "Full registration changeset, including password hashing (spec 003)."
  def registration_changeset(player, attrs) do
    player
    |> cast(attrs, [
      :first_name,
      :last_name,
      :date_of_birth,
      :gender,
      :email,
      :mobile_number,
      :profile_picture_path,
      :location,
      :country,
      :preferred_venue_id,
      :other_venue_name,
      :username,
      :notification_preference,
      :region_id,
      :password
    ])
    |> validate_required([
      :first_name,
      :last_name,
      :date_of_birth,
      :gender,
      :email,
      :mobile_number,
      :location,
      :country,
      :username,
      :notification_preference,
      :region_id,
      :password
    ])
    |> validate_venue_selection()
    |> validate_other_venue_not_duplicate()
    |> validate_inclusion(:gender, @genders)
    |> validate_inclusion(:notification_preference, @notification_preferences)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_format(:country, ~r/^[A-Z]{2}$/,
      message: "must be a 2-letter ISO country code (e.g. KE)"
    )
    |> PasswordValidator.validate_password(:password)
    |> validate_age()
    |> normalize_mobile_number()
    |> unique_constraint(:username,
      name: :players_lower_username_index,
      message: "has already been taken"
    )
    |> unique_constraint(:email,
      name: :players_lower_email_index,
      message: "has already been taken"
    )
    |> unique_constraint(:mobile_number, message: "has already been taken")
    |> foreign_key_constraint(:preferred_venue_id)
    |> hash_password()
  end

  @doc "Sets a new password after a reset-password link is verified (spec 011)."
  def reset_password_changeset(player, attrs) do
    player
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_confirmation(:password, message: "does not match")
    |> PasswordValidator.validate_password(:password)
    |> hash_password()
  end

  @doc "Updates just the notification preference (spec 003 US2)."
  def notification_preference_changeset(player, attrs) do
    player
    |> cast(attrs, [:notification_preference])
    |> validate_required([:notification_preference])
    |> validate_inclusion(:notification_preference, @notification_preferences)
  end

  @doc "Updates the player-editable personal details: username, date of birth, town."
  def personal_details_changeset(player, attrs) do
    player
    |> cast(attrs, [:username, :date_of_birth, :location])
    |> validate_required([:username, :date_of_birth, :location])
    |> validate_age()
    |> unique_constraint(:username,
      name: :players_lower_username_index,
      message: "has already been taken"
    )
  end

  @doc "Updates just the region (spec 003 US3) — caller (`Accounts.change_region/2`) enforces the region-lock before calling this."
  def region_changeset(player, attrs) do
    player
    |> cast(attrs, [:region_id])
    |> validate_required([:region_id])
    |> foreign_key_constraint(:region_id)
  end

  @doc """
  Updates just the preferred venue — always allowed, independent of the
  region lock, since a venue is only meaningful within the player's current
  region. Clears any free-text `other_venue_name` so the picked venue is the
  single source of truth.
  """
  def venue_changeset(player, attrs) do
    player
    |> cast(attrs, [:preferred_venue_id])
    |> validate_required([:preferred_venue_id])
    |> put_change(:other_venue_name, nil)
    |> foreign_key_constraint(:preferred_venue_id)
  end

  @doc """
  Updates region and preferred venue together — used when the player
  changes region, since a venue from their old region no longer applies.
  Caller (`Accounts.change_region_and_venue/3`) enforces the region-lock
  before calling this.
  """
  def region_and_venue_changeset(player, attrs) do
    player
    |> cast(attrs, [:region_id, :preferred_venue_id])
    |> validate_required([:region_id, :preferred_venue_id])
    |> put_change(:other_venue_name, nil)
    |> foreign_key_constraint(:region_id)
    |> foreign_key_constraint(:preferred_venue_id)
  end

  @doc "Sets a new password for a signed-in player after confirming their current one."
  def update_password_changeset(player, attrs) do
    player
    |> cast(attrs, [:current_password, :password, :password_confirmation])
    |> validate_required([:current_password, :password, :password_confirmation])
    |> validate_confirmation(:password, message: "does not match")
    |> PasswordValidator.validate_password(:password)
    |> validate_current_password()
    |> hash_password()
  end

  defp validate_current_password(changeset) do
    case get_change(changeset, :current_password) do
      nil ->
        changeset

      current_password ->
        if Bcrypt.verify_pass(current_password, changeset.data.hashed_password) do
          changeset
        else
          add_error(changeset, :current_password, "is incorrect")
        end
    end
  end

  @doc """
  Clears PII and marks `player` anonymized (spec 010 FR-004/FR-007).
  Placeholder `email`/`mobile_number`/`username` are derived from the
  player's own id to stay unique without a DB round-trip; `location` gets a
  fixed placeholder since it's `NOT NULL` but carries no uniqueness
  constraint.
  """
  def anonymize_changeset(player) do
    id_fragment = String.slice(player.id, 0, 8)

    player
    |> cast(
      %{
        first_name: "Former",
        last_name: "Player",
        email: "anonymized-#{id_fragment}@cuevolution.invalid",
        mobile_number: "+000000#{id_fragment}",
        profile_picture_path: nil,
        location: "Anonymized",
        username: "former-player-#{id_fragment}",
        anonymized_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      [
        :first_name,
        :last_name,
        :email,
        :mobile_number,
        :profile_picture_path,
        :location,
        :username,
        :anonymized_at
      ]
    )
    |> validate_required([
      :first_name,
      :last_name,
      :email,
      :mobile_number,
      :location,
      :username,
      :anonymized_at
    ])
    |> unique_constraint(:username, name: :players_lower_username_index)
    |> unique_constraint(:email, name: :players_lower_email_index)
    |> unique_constraint(:mobile_number)
  end

  defp validate_age(changeset) do
    case get_field(changeset, :date_of_birth) do
      nil ->
        changeset

      dob ->
        if age_in_years(dob) >= @minimum_age do
          changeset
        else
          add_error(changeset, :date_of_birth, "must be at least #{@minimum_age} years old")
        end
    end
  end

  defp age_in_years(dob) do
    today = Date.utc_today()
    age = today.year - dob.year

    if {today.month, today.day} < {dob.month, dob.day}, do: age - 1, else: age
  end

  defp validate_venue_selection(changeset) do
    preferred_venue_id = get_field(changeset, :preferred_venue_id)
    other_venue_name = get_field(changeset, :other_venue_name)
    other_present? = other_venue_name && String.trim(other_venue_name) != ""

    cond do
      preferred_venue_id && other_present? ->
        add_error(changeset, :preferred_venue_id, "choose either a venue or \"Other\", not both")

      preferred_venue_id || other_present? ->
        changeset

      true ->
        add_error(changeset, :preferred_venue_id, "select a venue or specify one under \"Other\"")
    end
  end

  # A DB-backed check inside an otherwise-pure changeset — deliberately so:
  # this is a cross-table check (this player's typed `other_venue_name`
  # against the `venues` table), which a simple unique index can't express,
  # and it needs to re-run identically every time this changeset is built —
  # including the display-only changeset `RegistrationLive` rebuilds from
  # raw attrs after a failed save — for the error to survive that rebuild.
  defp validate_other_venue_not_duplicate(changeset) do
    region_id = get_field(changeset, :region_id)
    other_venue_name = get_field(changeset, :other_venue_name)
    other_present? = other_venue_name && String.trim(other_venue_name) != ""

    if region_id && other_present? &&
         Venues.venue_name_taken_in_region?(region_id, other_venue_name) do
      add_error(
        changeset,
        :other_venue_name,
        "is already a listed venue — please select it instead of entering it as \"Other\""
      )
    else
      changeset
    end
  end

  defp normalize_mobile_number(changeset) do
    case get_change(changeset, :mobile_number) do
      nil ->
        changeset

      raw ->
        region_code = get_field(changeset, :country)

        case PhoneNumber.normalize(raw, region_code) do
          {:ok, e164} -> put_change(changeset, :mobile_number, e164)
          :error -> add_error(changeset, :mobile_number, "is not a valid mobile number")
        end
    end
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
