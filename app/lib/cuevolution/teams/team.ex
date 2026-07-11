defmodule Cuevolution.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "teams" do
    field :name, :string
    field :roster_locked_at, :utc_datetime

    belongs_to :region, Cuevolution.Accounts.Region
    belongs_to :captain, Cuevolution.Accounts.Player
    has_many :roster, Cuevolution.Accounts.Player, foreign_key: :team_id

    timestamps()
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :region_id, :captain_id])
    |> validate_required([:name, :region_id, :captain_id])
  end
end
