defmodule Cuevolution.Competitions.Stage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stages" do
    field :name, :string
    field :order, :integer
    field :completion_deadline, :date

    timestamps()
  end

  @doc "Stages are seeded and effectively read-only in application code; this changeset exists mainly for admin tooling, not general writes."
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name, :order, :completion_deadline])
    |> validate_required([:name, :order])
    |> unique_constraint(:name)
    |> unique_constraint(:order)
  end

  @doc "Every stage name that behaves like a Grassroots round — venue-scoped round-robin groups, male-only, the deadline-driven auto-draw formula."
  def grassroots_round_names, do: ["Grassroots", "Grassroots Round 2"]

  @doc "Every round-robin (group-based, non-knockout) stage name — the two Grassroots rounds plus Regional."
  def round_robin_stage_names, do: grassroots_round_names() ++ ["Regional"]

  @doc "True if `stage` behaves like a Grassroots round (see `grassroots_round_names/0`)."
  def grassroots?(%__MODULE__{name: name}), do: name in grassroots_round_names()

  @doc "True if `stage` is round-robin/group-based rather than knockout-bracket-based."
  def round_robin?(%__MODULE__{name: name}), do: name in round_robin_stage_names()
end
