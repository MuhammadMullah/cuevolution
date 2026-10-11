defmodule Cuevolution.Competitions.VenueEarlyClosure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ~w(male female team)

  @moduledoc """
  A tournament director's explicit sign-off that one venue's groups (for a
  given stage/category) may be closed before the stage's completion
  deadline, even though not every fixture is verified — e.g. a venue that
  finished all its matches on paper but didn't get results entered in
  time. Presence of a row is the override; `Competitions.final_groups/3`
  treats a venue holding one the same way it treats a deadline that's
  already passed. It never relaxes anything else — a group still only
  contributes qualifiers who actually played (see `played_group_member_ids/2`).
  """
  schema "venue_early_closures" do
    field :category, :string

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :admin, Cuevolution.Accounts.Admin

    timestamps(updated_at: false)
  end

  def changeset(early_closure, attrs) do
    early_closure
    |> cast(attrs, [:stage_id, :venue_id, :category, :admin_id])
    |> validate_required([:stage_id, :venue_id, :category, :admin_id])
    |> validate_inclusion(:category, @categories)
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:admin_id)
    |> unique_constraint([:stage_id, :venue_id, :category],
      name: :venue_early_closures_unique_index
    )
  end
end
