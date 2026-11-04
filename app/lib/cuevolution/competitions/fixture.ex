defmodule Cuevolution.Competitions.Fixture do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fixtures" do
    field :scheduled_at, :utc_datetime
    field :match_id, :string
    field :status, :string, default: "scheduled"
    field :walkover_kind, :string
    # Circuit bracket fields (spec 014). `slot` is the match number within its
    # round; the routing columns say where this match's winner and loser go,
    # which is what makes double elimination expressible at all. A nil route
    # means that outcome ends the player's run.
    field :slot, :integer
    field :bye, :boolean, default: false
    # Running frame count while the match is in play: %{"a" => n, "b" => n}.
    field :live_score, :map
    # Optional capture fields from the SP Points & Standings brief: which table
    # the match was played on, when it finished, and any break-and-clears. None
    # of them affects the points or the standings.
    field :table_number, :integer
    field :ended_at, :utc_datetime
    field :break_and_clears, :integer
    field :winner_to_side, :string
    field :loser_to_side, :string

    belongs_to :round, Cuevolution.Competitions.Round
    belongs_to :participant_a, Cuevolution.Competitions.StageParticipation
    belongs_to :participant_b, Cuevolution.Competitions.StageParticipation
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :result, Cuevolution.Competitions.MatchResult
    belongs_to :winner_to_fixture, __MODULE__, foreign_key: :winner_to_fixture_id
    belongs_to :loser_to_fixture, __MODULE__, foreign_key: :loser_to_fixture_id

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
    |> validate_inclusion(
      :status,
      ~w(scheduled live completed verified walkover postponed abandoned)
    )
    |> validate_inclusion(:walkover_kind, ~w(single double))
    |> foreign_key_constraint(:round_id)
    |> foreign_key_constraint(:participant_a_id)
    |> foreign_key_constraint(:participant_b_id)
    |> foreign_key_constraint(:venue_id)
    |> check_constraint(:status, name: :fixture_status_valid)
    |> check_constraint(:walkover_kind, name: :walkover_kind_valid)
    |> check_constraint(:participant_a_id, name: :participants_must_differ)
    |> unique_constraint([:round_id, :participant_a_id, :participant_b_id],
      name: :fixtures_round_participants_unique_index,
      message: "this pairing already exists in this round"
    )
  end

  def auto_generate_changeset(fixture, attrs, %{participant_a: pa, participant_b: pb}) do
    fixture
    |> cast(attrs, [:round_id, :participant_a_id, :participant_b_id])
    |> put_change(:match_id, Map.fetch!(attrs, :match_id))
    |> put_change(:status, "scheduled")
    |> validate_required([:round_id, :participant_a_id, :participant_b_id, :match_id])
    |> validate_same_category_and_stage(pa, pb)
    |> validate_inclusion(
      :status,
      ~w(scheduled live completed verified walkover postponed abandoned)
    )
    |> foreign_key_constraint(:round_id)
    |> foreign_key_constraint(:participant_a_id)
    |> foreign_key_constraint(:participant_b_id)
    |> unique_constraint(:match_id)
    |> check_constraint(:status, name: :fixture_status_valid)
    |> check_constraint(:walkover_kind, name: :walkover_kind_valid)
  end

  @doc """
  Sets a bracket match's start time. Unlike `update_changeset/2` this needs no
  venue — a circuit is played at one venue, and the bracket fixture carries
  none.
  """
  def schedule_changeset(fixture, attrs) do
    fixture
    |> cast(attrs, [:scheduled_at, :table_number, :ended_at, :break_and_clears])
    |> validate_number(:table_number, greater_than: 0)
    |> validate_number(:break_and_clears, greater_than_or_equal_to: 0)
    |> check_constraint(:table_number, name: :fixtures_table_number_positive)
    |> check_constraint(:break_and_clears, name: :fixtures_break_and_clears_not_negative)
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
