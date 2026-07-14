defmodule Cuevolution.Competitions.StageParticipation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stage_participations" do
    field :category, :string
    field :joined_at, :utc_datetime

    belongs_to :player, Cuevolution.Accounts.Player
    belongs_to :team, Cuevolution.Teams.Team
    belongs_to :region, Cuevolution.Accounts.Region
    belongs_to :stage, Cuevolution.Competitions.Stage

    timestamps()
  end

  @categories ~w(male female team)

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [:player_id, :team_id, :region_id, :stage_id, :category, :joined_at])
    |> validate_required([:region_id, :stage_id, :category, :joined_at])
    |> validate_inclusion(:category, @categories)
    |> validate_exactly_one_participant()
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:region_id)
    |> foreign_key_constraint(:stage_id)
    |> check_constraint(:player_id, name: :exactly_one_participant_type)
  end

  defp validate_exactly_one_participant(changeset) do
    player_id = get_field(changeset, :player_id)
    team_id = get_field(changeset, :team_id)

    case {player_id, team_id} do
      {nil, nil} ->
        add_error(changeset, :player_id, "either player or team must be set")

      {p, t} when not is_nil(p) and not is_nil(t) ->
        add_error(changeset, :player_id, "cannot set both player and team")

      _ ->
        changeset
    end
  end
end
