defmodule Cuevolution.Accounts.Admin do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cuevolution.Accounts.PasswordValidator
  alias Cuevolution.Accounts.PhoneNumber

  @roles ~w(super_admin tournament_director regional_coordinator venue_representative)
  @invitable_roles @roles -- ["super_admin"]
  @permissions %{
    manage_admins: ["super_admin", "tournament_director"],
    manage_super_admins: ["super_admin"],
    manage_fixtures: ["super_admin", "regional_coordinator", "venue_representative"],
    record_results: ["super_admin", "regional_coordinator", "venue_representative"],
    approve_results: ["super_admin", "regional_coordinator"],
    manage_stages: ["super_admin", "tournament_director", "regional_coordinator"],
    manage_groups: ["super_admin", "tournament_director", "regional_coordinator"],
    view_directory: ["super_admin", "tournament_director", "regional_coordinator"],
    anonymize_users: ["super_admin", "tournament_director"],
    manage_venues: ["super_admin", "tournament_director", "regional_coordinator"],
    manage_teams: ["super_admin", "tournament_director", "regional_coordinator"],
    manage_players: ["super_admin", "tournament_director", "regional_coordinator"]
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admins" do
    field :email, :string
    field :role, :string
    field :mobile_number, :string
    field :suspended_at, :utc_datetime
    field :removed_at, :utc_datetime
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    belongs_to :venue, Cuevolution.Venues.Venue

    timestamps()
  end

  def roles, do: @roles
  def invitable_roles, do: @invitable_roles
  def permissions, do: @permissions

  def can?(%__MODULE__{role: role} = admin, permission),
    do: active?(admin) and role in Map.get(@permissions, permission, [])

  def can?(_, _), do: false

  def manageable_by?(%__MODULE__{role: actor_role}, %__MODULE__{role: target_role}) do
    actor_role == "super_admin" or
      (actor_role == "tournament_director" and target_role != "super_admin")
  end

  def manageable_by?(_, _), do: false

  def active?(%__MODULE__{suspended_at: nil, removed_at: nil}), do: true
  def active?(%__MODULE__{}), do: false

  def suspended?(%__MODULE__{suspended_at: %DateTime{}}), do: true
  def suspended?(%__MODULE__{}), do: false

  def removed?(%__MODULE__{removed_at: %DateTime{}}), do: true
  def removed?(%__MODULE__{}), do: false

  @doc ~S(Human-readable label for a role value, e.g. "tournament_director" -> "Tournament Director".)
  def role_label(role) do
    case role do
      "super_admin" -> "Super Admin"
      "tournament_director" -> "Tournament Director"
      "regional_coordinator" -> "Regional Coordinator"
      "venue_representative" -> "Venue Representative"
      _ -> role |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  @doc "Whether `admin` has been invited but hasn't yet completed account setup."
  def pending?(%__MODULE__{hashed_password: nil}), do: true
  def pending?(%__MODULE__{}), do: false

  @doc "Full registration changeset, including password hashing — used to create the initial super admin (see priv/repo/seeds)."
  def registration_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password, :role])
    |> validate_required([:email, :password, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_inclusion(:role, @roles)
    |> PasswordValidator.validate_password(:password)
    |> unique_constraint(:email)
    |> hash_password()
  end

  @doc """
  Creates a pending admin invited by a super admin: just an email and a
  role, no password yet — they complete setup via `setup_changeset/2` after
  following the emailed link.
  """
  def invite_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :role, :venue_id])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_inclusion(:role, @invitable_roles)
    |> validate_venue_assignment()
    |> unique_constraint(:email)
  end

  def venue_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:venue_id])
    |> validate_required(:venue_id)
    |> foreign_key_constraint(:venue_id)
  end

  @doc "Completes an invited admin's account setup: sets password and mobile number."
  def setup_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:password, :password_confirmation, :mobile_number])
    |> validate_required([:password, :password_confirmation, :mobile_number])
    |> validate_confirmation(:password, message: "does not match")
    |> PasswordValidator.validate_password(:password)
    |> normalize_mobile_number()
    |> unique_constraint(:mobile_number)
    |> hash_password()
  end

  defp normalize_mobile_number(changeset) do
    case get_change(changeset, :mobile_number) do
      nil ->
        changeset

      raw ->
        case PhoneNumber.normalize(raw) do
          {:ok, e164} -> put_change(changeset, :mobile_number, e164)
          :error -> add_error(changeset, :mobile_number, "is not a valid mobile number")
        end
    end
  end

  defp validate_venue_assignment(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :venue_id)} do
      {"venue_representative", nil} ->
        add_error(changeset, :venue_id, "must be assigned to a venue")

      {role, venue_id} when role != "venue_representative" and not is_nil(venue_id) ->
        add_error(changeset, :venue_id, "is only used for venue representatives")

      _ ->
        changeset
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
