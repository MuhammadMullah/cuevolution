defmodule Cuevolution.Competitions.Draw do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(male female team)
  @states ~w(draft previewed approved published)

  schema "draws" do
    field :category, :string
    field :state, :string, default: "draft"
    field :random_seed, :string
    field :group_count_override, :integer
    field :formula_group_count, :integer
    field :redraw_count, :integer, default: 0

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :region, Cuevolution.Accounts.Region

    # Microsecond precision (not the app default `:utc_datetime`) — a
    # redraw's new draft can be inserted within the same second as the
    # superseded draw's last update, and `Competitions.latest_draw/3` picks
    # the current draw purely by `ORDER BY inserted_at DESC`.
    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states

  @doc """
  `venue_id` scopes a Grassroots draw to one venue; `region_id` scopes a
  Regional draw to one region (combining every category drawn there —
  including "team", never split by gender). Exactly one of the two must be
  set, mirroring `stage_participations`' `exactly_one_participant_type`.
  """
  def changeset(draw, attrs) do
    draw
    |> cast(attrs, [
      :stage_id,
      :venue_id,
      :region_id,
      :category,
      :state,
      :random_seed,
      :group_count_override,
      :formula_group_count,
      :redraw_count
    ])
    |> validate_required([:stage_id, :category, :state, :formula_group_count])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:state, @states)
    |> validate_number(:formula_group_count, greater_than: 0)
    |> validate_number(:group_count_override, greater_than: 0)
    |> validate_number(:redraw_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> validate_exactly_one_scope()
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:region_id)
    |> check_constraint(:state, name: :draw_state_valid)
    |> check_constraint(:category, name: :draw_category_valid)
    |> check_constraint(:formula_group_count, name: :draw_group_counts_positive)
    |> check_constraint(:region_id, name: :draws_scope_present)
  end

  defp validate_exactly_one_scope(changeset) do
    venue_id = get_field(changeset, :venue_id)
    region_id = get_field(changeset, :region_id)

    case {venue_id, region_id} do
      {nil, nil} ->
        add_error(changeset, :venue_id, "either a venue or a region must be set")

      {v, r} when not is_nil(v) and not is_nil(r) ->
        add_error(changeset, :venue_id, "cannot set both a venue and a region")

      _ ->
        changeset
    end
  end
end
