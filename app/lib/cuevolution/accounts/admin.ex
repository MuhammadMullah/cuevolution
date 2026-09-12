defmodule Cuevolution.Accounts.Admin do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cuevolution.Accounts.PasswordValidator
  alias Cuevolution.Accounts.PhoneNumber

  @roles ~w(super_admin tournament_manager regional_coordinator venue_representative)
  @invitable_roles @roles -- ["super_admin"]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admins" do
    field :email, :string
    field :role, :string
    field :mobile_number, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    timestamps()
  end

  def roles, do: @roles
  def invitable_roles, do: @invitable_roles

  @doc ~S(Human-readable label for a role value, e.g. "tournament_manager" -> "Tournament Manager".)
  def role_label(role) do
    role
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
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
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_inclusion(:role, @invitable_roles)
    |> unique_constraint(:email)
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
