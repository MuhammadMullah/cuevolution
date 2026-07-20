defmodule Cuevolution.Competitions.CuevoPointsEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cuevo_points_entries" do
    field :points, :integer
    field :prior_value, :map

    belongs_to :participant, Cuevolution.Competitions.StageParticipation
    belongs_to :match_result, Cuevolution.Competitions.MatchResult
    belongs_to :match_frame, Cuevolution.Competitions.MatchFrame
    belongs_to :recorded_by_admin, Cuevolution.Accounts.Admin

    timestamps()
  end

  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :participant_id,
      :match_result_id,
      :match_frame_id,
      :points,
      :recorded_by_admin_id
    ])
    |> validate_required([:participant_id, :match_result_id, :points, :recorded_by_admin_id])
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:match_result_id)
    |> foreign_key_constraint(:match_frame_id)
    |> foreign_key_constraint(:recorded_by_admin_id)
  end

  def correction_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:points, :prior_value])
    |> validate_required([:points])
  end
end
