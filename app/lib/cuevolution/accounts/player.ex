defmodule Cuevolution.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cuevolution.Accounts.PasswordValidator
  alias Cuevolution.Accounts.PhoneNumber

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
