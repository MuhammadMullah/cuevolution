defmodule Cuevolution.Competitions.StageCapacityConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stage_capacity_configs" do
    field :category, :string
    field :capacity_limit, :integer
    field :current_count, :integer, default: 0

    belongs_to :stage, Cuevolution.Competitions.Stage

    timestamps()
  end

  @categories ~w(male female team)

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:stage_id, :category, :capacity_limit])
    |> validate_required([:stage_id, :category, :capacity_limit])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:capacity_limit, greater_than: 0)
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:stage_id, :category])
  end
end
