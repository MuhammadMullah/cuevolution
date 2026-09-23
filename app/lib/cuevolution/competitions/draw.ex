defmodule Cuevolution.Competitions.Draw do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(male female)
  @states ~w(draft previewed approved published)

  schema "draws" do
    field :category, :string
    field :state, :string, default: "draft"
    field :random_seed, :string
    field :group_count_override, :integer
    field :formula_group_count, :integer

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :venue, Cuevolution.Venues.Venue

    timestamps()
  end

  def states, do: @states

  def changeset(draw, attrs) do
    draw
    |> cast(attrs, [
      :stage_id,
      :venue_id,
      :category,
      :state,
      :random_seed,
      :group_count_override,
      :formula_group_count
    ])
    |> validate_required([:stage_id, :venue_id, :category, :state, :formula_group_count])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:state, @states)
    |> validate_number(:formula_group_count, greater_than: 0)
    |> validate_number(:group_count_override, greater_than: 0)
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:venue_id)
    |> check_constraint(:state, name: :draw_state_valid)
    |> check_constraint(:category, name: :draw_category_valid)
    |> check_constraint(:formula_group_count, name: :draw_group_counts_positive)
  end
end
