defmodule Cuevolution.Competitions.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :region, Cuevolution.Accounts.Region
    has_many :group_memberships, Cuevolution.Competitions.GroupMembership
    has_one :knockout_bracket, Cuevolution.Competitions.KnockoutBracket

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:stage_id, :region_id, :name])
    |> validate_required([:stage_id, :region_id, :name])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:region_id)
    |> unique_constraint([:stage_id, :region_id, :name])
  end
end
