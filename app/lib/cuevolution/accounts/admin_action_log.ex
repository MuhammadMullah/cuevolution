defmodule Cuevolution.Accounts.AdminActionLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_action_logs" do
    field :action_type, :string
    field :entity_type, :string
    field :entity_id, :binary_id
    field :prior_value, :map
    field :new_value, :map
    field :actor_type, :string, default: "admin"
    belongs_to :admin, Cuevolution.Accounts.Admin

    timestamps(updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :admin_id,
      :action_type,
      :entity_type,
      :entity_id,
      :prior_value,
      :new_value,
      :actor_type
    ])
    |> validate_required([:action_type, :entity_type, :entity_id, :actor_type])
    |> validate_inclusion(:actor_type, ~w(admin system))
    |> validate_actor_admin()
  end

  defp validate_actor_admin(changeset) do
    case {get_field(changeset, :actor_type), get_field(changeset, :admin_id)} do
      {"admin", nil} -> add_error(changeset, :admin_id, "is required for admin actions")
      {"system", nil} -> changeset
      {"system", _admin_id} -> add_error(changeset, :admin_id, "must be empty for system actions")
      _ -> changeset
    end
  end
end
