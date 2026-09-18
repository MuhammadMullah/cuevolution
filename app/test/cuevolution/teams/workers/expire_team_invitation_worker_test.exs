defmodule Cuevolution.Teams.Workers.ExpireTeamInvitationWorkerTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.TeamInvitation
  alias Cuevolution.Teams.Workers.ExpireTeamInvitationWorker

  test "flips a pending invitation to expired" do
    team = insert(:team)
    invitee = insert(:player)
    {:ok, invitation} = Teams.invite_player(team, invitee)

    assert :ok = perform_job(ExpireTeamInvitationWorker, %{"invitation_id" => invitation.id})

    assert Repo.get!(TeamInvitation, invitation.id).status == "expired"
  end

  test "is a no-op when the invitation was already accepted" do
    team = insert(:team)
    invitee = insert(:player)
    {:ok, invitation} = Teams.invite_player(team, invitee)
    {:ok, _player} = Teams.accept_invitation(invitation, invitee)

    assert :ok = perform_job(ExpireTeamInvitationWorker, %{"invitation_id" => invitation.id})

    assert Repo.get!(TeamInvitation, invitation.id).status == "accepted"
  end

  test "is a no-op when the invitation no longer exists" do
    assert :ok =
             perform_job(ExpireTeamInvitationWorker, %{
               "invitation_id" => Ecto.UUID.generate()
             })
  end
end
