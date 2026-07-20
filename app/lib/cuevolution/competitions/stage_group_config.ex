defmodule Cuevolution.Competitions.StageGroupConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stage_group_configs" do
    field :category, :string
    field :group_size, :integer, default: 8
    field :advancer_count, :integer, default: 2

    belongs_to :stage, Cuevolution.Competitions.Stage

    timestamps()
  end

  @categories ~w(male female team)

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:stage_id, :category, :group_size, :advancer_count])
    |> validate_required([:stage_id, :category, :group_size, :advancer_count])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:group_size, greater_than: 0)
    |> validate_number(:advancer_count, greater_than: 0)
    |> foreign_key_constraint(:stage_id)
    |> unique_constraint([:stage_id, :category])
  end
end
