defmodule Cuevolution.Competitions.KnockoutBracket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(male female team)

  schema "knockout_brackets" do
    field :category, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    has_many :rounds, Cuevolution.Competitions.Round

    timestamps()
  end

  @doc "One bracket per stage+category (Circuit/Finals) — covers every capacity-admitted entrant of that stage+category, no group relationship (spec 006 FR-013)."
  def changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:stage_id, :category])
    |> validate_required([:stage_id, :category])
    |> validate_inclusion(:category, @categories)
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:stage_id, :category])
  end
end
