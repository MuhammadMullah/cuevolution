defmodule Cuevolution.Venues.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "venues" do
    field :name, :string
    field :active, :boolean, default: true

    belongs_to :region, Cuevolution.Accounts.Region

    timestamps()
  end

  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :active, :region_id])
    |> validate_required([:name, :region_id])
    |> unique_constraint([:name, :region_id],
      name: :venues_region_lower_name_active_index,
      message: "already exists in this region"
    )
  end
end
