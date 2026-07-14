defmodule Cuevolution.Competitions.Round do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rounds" do
    field :name, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :group, Cuevolution.Competitions.Group
    has_many :fixtures, Cuevolution.Competitions.Fixture

    timestamps()
  end

  def changeset(round, attrs) do
    round
    |> cast(attrs, [:stage_id, :group_id, :name])
    |> validate_required([:stage_id, :name])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:group_id)
  end
end
