defmodule Cuevolution.Competitions.Round do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rounds" do
    field :name, :string
    # The bracket engine's short code for this round — "W1", "L4", "R32", "SF",
    # "F". The stable identity the SP Points rules are written against; nil for
    # a round-robin round, which has no bracket position.
    field :code, :string
    # Set only for Circuit double-elimination rounds (spec 014); nil for the
    # round-robin rounds at Grassroots/Regional.
    field :bracket_side, :string
    field :sequence, :integer
    field :race_to, :integer

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :group, Cuevolution.Competitions.Group
    belongs_to :knockout_bracket, Cuevolution.Competitions.KnockoutBracket
    has_many :fixtures, Cuevolution.Competitions.Fixture

    timestamps()
  end

  @doc """
  Exactly one of `group_id` (Grassroots/Regional round-robin round) or
  `knockout_bracket_id` (Circuit/Finals knockout round) must be set — the DB
  `exactly_one_round_context` CHECK is the source of truth; this changeset
  gives a friendlier error at the application layer.
  """
  def changeset(round, attrs) do
    round
    |> cast(attrs, [
      :stage_id,
      :group_id,
      :knockout_bracket_id,
      :name,
      :code,
      :bracket_side,
      :sequence,
      :race_to
    ])
    |> validate_inclusion(:bracket_side, ~w(winners losers knockout))
    |> validate_number(:race_to, greater_than: 0)
    |> validate_required([:stage_id, :name])
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:knockout_bracket_id)
    |> validate_exactly_one_context()
    |> check_constraint(:group_id, name: :exactly_one_round_context)
  end

  defp validate_exactly_one_context(changeset) do
    group_id = get_field(changeset, :group_id)
    bracket_id = get_field(changeset, :knockout_bracket_id)

    case {group_id, bracket_id} do
      {nil, nil} ->
        add_error(changeset, :group_id, "must set either a group or a knockout bracket")

      {gid, bid} when not is_nil(gid) and not is_nil(bid) ->
        add_error(changeset, :group_id, "cannot set both a group and a knockout bracket")

      _ ->
        changeset
    end
  end
end
