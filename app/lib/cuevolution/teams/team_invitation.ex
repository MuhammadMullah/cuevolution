defmodule Cuevolution.Teams.TeamInvitation do
  @moduledoc """
  A captain's invitation for a player to join a team's roster. The player
  must accept before `players.team_id` changes — see `Cuevolution.Teams`
  `invite_player/2`, `accept_invitation/2`, `decline_invitation/2`,
  `cancel_invitation/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending accepted declined expired cancelled)

  schema "team_invitations" do
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :responded_at, :utc_datetime

    belongs_to :team, Cuevolution.Teams.Team
    belongs_to :player, Cuevolution.Accounts.Player
    belongs_to :invited_by, Cuevolution.Accounts.Player

    timestamps()
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:team_id, :player_id, :invited_by_id, :status, :expires_at, :responded_at])
    |> validate_required([:team_id, :player_id, :status, :expires_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:invited_by_id)
    |> unique_constraint([:team_id, :player_id],
      name: :team_invitations_one_pending_per_team_player,
      message: "already has a pending invitation from this team"
    )
  end
end
