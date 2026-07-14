defmodule Cuevolution.Competitions.KnockoutBracket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "knockout_brackets" do
    belongs_to :group, Cuevolution.Competitions.Group

    timestamps()
  end

  def changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:group_id])
    |> validate_required([:group_id])
    |> foreign_key_constraint(:group_id)
    |> unique_constraint(:group_id)
  end
end
