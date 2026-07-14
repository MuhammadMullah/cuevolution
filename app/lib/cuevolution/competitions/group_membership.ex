defmodule Cuevolution.Competitions.GroupMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "group_memberships" do
    belongs_to :group, Cuevolution.Competitions.Group
    belongs_to :stage_participation, Cuevolution.Competitions.StageParticipation

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:group_id, :stage_participation_id])
    |> validate_required([:group_id, :stage_participation_id])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:stage_participation_id)
    |> unique_constraint([:group_id, :stage_participation_id])
  end
end
