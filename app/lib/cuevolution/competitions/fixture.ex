defmodule Cuevolution.Competitions.Fixture do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fixtures" do
    field :scheduled_at, :utc_datetime

    belongs_to :round, Cuevolution.Competitions.Round
    belongs_to :participant_a, Cuevolution.Competitions.StageParticipation
    belongs_to :participant_b, Cuevolution.Competitions.StageParticipation
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :result, Cuevolution.Competitions.MatchResult

    timestamps()
  end

  @doc """
  Create changeset. `participants` is `%{participant_a: %StageParticipation{}, participant_b: %StageParticipation{}}`,
  preloaded by the caller (`Competitions.enter_fixtures/2`) — validated here
  rather than re-queried, keeping this changeset pure/testable.
  """
  def changeset(fixture, attrs, %{participant_a: pa, participant_b: pb}) do
    fixture
    |> cast(attrs, [:round_id, :participant_a_id, :participant_b_id, :venue_id, :scheduled_at])
    |> validate_required([
      :round_id,
      :participant_a_id,
      :participant_b_id,
      :venue_id,
      :scheduled_at
    ])
    |> validate_same_category_and_stage(pa, pb)
    |> foreign_key_constraint(:round_id)
    |> foreign_key_constraint(:participant_a_id)
    |> foreign_key_constraint(:participant_b_id)
    |> foreign_key_constraint(:venue_id)
    |> check_constraint(:participant_a_id, name: :participants_must_differ)
    |> unique_constraint([:round_id, :participant_a_id, :participant_b_id],
      name: :fixtures_round_participants_unique_index,
      message: "this pairing already exists in this round"
    )
  end

  @doc "Edit changeset — venue/schedule only. Fixtures with a result are locked; `Competitions.update_fixture/2` enforces that before calling this."
  def update_changeset(fixture, attrs) do
    fixture
    |> cast(attrs, [:venue_id, :scheduled_at])
    |> validate_required([:venue_id, :scheduled_at])
    |> foreign_key_constraint(:venue_id)
  end

  @doc "Links a freshly-recorded `MatchResult` to this fixture — `Competitions.record_result/3` calls this inside the same `Ecto.Multi` as the result insert."
  def result_changeset(fixture, result_id) do
    fixture
    |> cast(%{result_id: result_id}, [:result_id])
    |> validate_required([:result_id])
    |> foreign_key_constraint(:result_id)
  end

  defp validate_same_category_and_stage(changeset, pa, pb) do
    cond do
      pa.category != pb.category ->
        add_error(changeset, :participant_b_id, "must be the same category as participant A")

      pa.stage_id != pb.stage_id ->
        add_error(changeset, :participant_b_id, "must be in the same stage as participant A")

      true ->
        changeset
    end
  end
end
