defmodule Cuevolution.Competitions.Stage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stages" do
    field :name, :string
    field :order, :integer

    timestamps()
  end

  @doc "Stages are seeded and effectively read-only in application code; this changeset exists mainly for admin tooling, not general writes."
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name, :order])
    |> validate_required([:name, :order])
    |> unique_constraint(:name)
    |> unique_constraint(:order)
  end
end
