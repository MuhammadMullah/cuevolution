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
    belongs_to :admin, Cuevolution.Accounts.Admin

    timestamps(updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:admin_id, :action_type, :entity_type, :entity_id, :prior_value, :new_value])
    |> validate_required([:admin_id, :action_type, :entity_type, :entity_id])
  end
end
