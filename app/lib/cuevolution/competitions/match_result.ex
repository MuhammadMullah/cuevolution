defmodule Cuevolution.Competitions.MatchResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_results" do
    field :score, :map
    field :prior_value, :map

    belongs_to :fixture, Cuevolution.Competitions.Fixture
    belongs_to :winner_participation, Cuevolution.Competitions.StageParticipation
    belongs_to :recorded_by_admin, Cuevolution.Accounts.Admin
    has_many :match_frames, Cuevolution.Competitions.MatchFrame
    has_many :cuevo_points_entries, Cuevolution.Competitions.CuevoPointsEntry

    timestamps()
  end

  def create_changeset(result, attrs) do
    result
    |> cast(attrs, [:fixture_id, :winner_participation_id, :score, :recorded_by_admin_id])
    |> validate_required([:fixture_id, :winner_participation_id, :recorded_by_admin_id])
    |> foreign_key_constraint(:fixture_id)
    |> foreign_key_constraint(:winner_participation_id)
    |> foreign_key_constraint(:recorded_by_admin_id)
    |> unique_constraint(:fixture_id,
      message: "a result has already been recorded for this fixture"
    )
  end

  @doc "Correction changeset — caller snapshots the pre-update struct into :prior_value before calling this."
  def correction_changeset(result, attrs) do
    result
    |> cast(attrs, [:winner_participation_id, :score, :prior_value])
    |> validate_required([:winner_participation_id])
  end
end
