defmodule Cuevolution.Competitions.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(male female team)

  schema "groups" do
    field :name, :string
    field :category, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :region, Cuevolution.Accounts.Region
    belongs_to :venue, Cuevolution.Venues.Venue
    has_many :group_memberships, Cuevolution.Competitions.GroupMembership

    timestamps()
  end

  @doc """
  `venue_id` is required for Grassroots-stage groups (venue-scoped pairing)
  and must be absent for Regional-stage groups (region-scoped pairing) —
  callers (`Competitions.create_group/1`) validate that stage-conditional
  rule; this changeset only enforces the always-true shape (required fields,
  category inclusion, uniqueness).
  """
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:stage_id, :region_id, :venue_id, :category, :name])
    |> validate_required([:stage_id, :region_id, :category, :name])
    |> validate_inclusion(:category, @categories)
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:region_id)
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint([:stage_id, :region_id, :category, :name],
      name: :groups_region_scoped_unique_index
    )
    |> unique_constraint([:stage_id, :venue_id, :category, :name],
      name: :groups_venue_scoped_unique_index
    )
  end
end
