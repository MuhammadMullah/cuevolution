defmodule Cuevolution.Competitions.MatchFrame do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_frames" do
    field :sequence, :integer

    belongs_to :match_result, Cuevolution.Competitions.MatchResult
    belongs_to :home_player, Cuevolution.Accounts.Player
    belongs_to :away_player, Cuevolution.Accounts.Player
    belongs_to :winner_player, Cuevolution.Accounts.Player

    timestamps()
  end

  def changeset(frame, attrs) do
    frame
    |> cast(attrs, [
      :match_result_id,
      :home_player_id,
      :away_player_id,
      :winner_player_id,
      :sequence
    ])
    |> validate_required([
      :match_result_id,
      :home_player_id,
      :away_player_id,
      :winner_player_id,
      :sequence
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> foreign_key_constraint(:match_result_id)
    |> foreign_key_constraint(:home_player_id)
    |> foreign_key_constraint(:away_player_id)
    |> foreign_key_constraint(:winner_player_id)
    |> check_constraint(:winner_player_id, name: :winner_must_be_home_or_away)
    |> unique_constraint([:match_result_id, :sequence])
  end
end
