defmodule Cuevolution.TeamsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Teams

  defp stage(name), do: Repo.get_by!(Stage, name: name)

  describe "create_team/2" do
    test "creates a team with the player as captain, region inherited from the captain" do
      captain = insert(:player)

      assert {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})

      assert team.name == "The Sharks"
      assert team.captain_id == captain.id
      assert team.region_id == captain.region_id
    end

    test "sets the captain's team_id to the new team" do
      captain = insert(:player)

      assert {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})

      assert Repo.get!(Player, captain.id).team_id == team.id
    end

    test "requires a name" do
      captain = insert(:player)

      assert {:error, changeset} = Teams.create_team(captain, %{"name" => ""})
      refute changeset.valid?
    end

    test "blocks a player who is already on a team from creating a second one" do
      captain = insert(:player)
      assert {:ok, _first_team} = Teams.create_team(captain, %{"name" => "First Team"})

      captain = Repo.get!(Player, captain.id)

      assert {:error, :already_on_a_team} = Teams.create_team(captain, %{"name" => "Second Team"})
    end
  end

  describe "add_player_to_roster/2" do
    test "rejects a player registered after the tournament cutoff" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      late_player = insert(:player, inserted_at: ~N[2026-09-21 08:00:00])

      assert {:error, :registration_closed} = Teams.add_player_to_roster(team, late_player)
      assert Repo.get!(Player, late_player.id).team_id == nil
    end

    test "adds a registered player with no team to the roster" do
      team = insert(:team)
      player = insert(:player, region_id: team.region_id, notification_preference: "email")

      assert {:ok, updated_player} = Teams.add_player_to_roster(team, player)
      assert updated_player.team_id == team.id

      notification =
        Repo.get_by!(Cuevolution.Notifications.Notification,
          player_id: player.id,
          event_type: "team_assignment"
        )

      assert notification.channel == "email"
      assert notification.payload["team_name"] == team.name
    end

    test "rejects a player who already belongs to another team" do
      captain_a = insert(:player)
      {:ok, team_a} = Teams.create_team(captain_a, %{"name" => "Team A"})
      team_b = insert(:team)

      member_of_a = Repo.get!(Player, captain_a.id)

      assert {:error, :already_on_a_team} = Teams.add_player_to_roster(team_b, member_of_a)
      assert Repo.get!(Player, member_of_a.id).team_id == team_a.id
    end

    test "rejects adding a 9th player once the roster is at the 8-player maximum" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Full Team"})

      # Captain already fills roster slot 1; 7 more brings it to the max of 8.
      for _ <- 1..7 do
        player = insert(:player, region_id: team.region_id)
        assert {:ok, _} = Teams.add_player_to_roster(team, player)
      end

      ninth_player = insert(:player, region_id: team.region_id)
      assert {:error, :roster_full} = Teams.add_player_to_roster(team, ninth_player)
    end
  end

  describe "eligible?/1" do
    test "a team with fewer than 5 players is ineligible" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Small Team"})

      for _ <- 1..3 do
        Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      end

      refute Teams.eligible?(team)
    end

    test "a team with 5 to 8 players is eligible" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Right-sized Team"})

      for _ <- 1..4 do
        Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      end

      assert Teams.eligible?(team)
    end

    test "eligibility is always derived live, never a stale cached value" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Growing Team"})

      refute Teams.eligible?(team)

      for _ <- 1..4 do
        Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      end

      assert Teams.eligible?(team)
    end
  end

  describe "remove_player_from_roster/2" do
    test "removes the player from the roster (team_id cleared)" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

      assert {:ok, updated} = Teams.remove_player_from_roster(team, member)
      assert updated.team_id == nil
    end

    test "eligibility auto-flips to false when roster drops below 5" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})

      members =
        for _ <- 1..4 do
          {:ok, member} =
            Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

          member
        end

      assert Teams.eligible?(team)

      [to_remove | _] = members
      Teams.remove_player_from_roster(team, to_remove)

      refute Teams.eligible?(team)
    end

    test "eligibility auto-restores once the roster returns to 5+" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})

      members =
        for _ <- 1..4 do
          {:ok, member} =
            Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

          member
        end

      [to_remove | _] = members
      Teams.remove_player_from_roster(team, to_remove)
      refute Teams.eligible?(team)

      Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      assert Teams.eligible?(team)
    end
  end

  describe "leave_team/2" do
    test "releases a non-captain player and notifies the captain with eligibility" do
      captain =
        insert(:player,
          inserted_at: ~N[2026-09-19 00:00:00],
          notification_preference: "email"
        )

      {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
      member = insert(:player, inserted_at: ~N[2026-09-19 00:00:00], region_id: team.region_id)
      assert {:ok, _member} = Teams.add_player_to_roster(team, member)

      assert {:ok, left} = Teams.leave_team(team, Repo.get!(Player, member.id))
      assert is_nil(left.team_id)

      notification =
        Repo.get_by!(Cuevolution.Notifications.Notification,
          player_id: captain.id,
          event_type: "team_player_left"
        )

      assert notification.channel == "email"
      assert notification.payload["team_name"] == team.name
      assert notification.payload["roster_count"] == 1
      assert notification.payload["eligible"] == false
    end

    test "does not allow the captain to leave" do
      captain = insert(:player, inserted_at: ~N[2026-09-19 00:00:00])
      {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})

      assert {:error, :captain_cannot_leave} =
               Teams.leave_team(team, Repo.get!(Player, captain.id))
    end
  end

  describe "roster freeze (spec 005 FR-008)" do
    test "add_player_to_roster/3 rejects once the roster is frozen" do
      team = insert(:team)
      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)

      assert {:error, :roster_frozen} =
               Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    end

    test "add_player_to_roster/3 succeeds when not frozen" do
      team = insert(:team)

      assert {:ok, _player} =
               Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    end

    test "remove_player_from_roster/3 rejects once the roster is frozen" do
      team = insert(:team)
      {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)

      assert {:error, :roster_frozen} = Teams.remove_player_from_roster(team, member)
    end

    test "remove_player_from_roster/3 succeeds when not frozen" do
      team = insert(:team)
      {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

      assert {:ok, _player} = Teams.remove_player_from_roster(team, member)
    end

    test "override_roster_change/4 bypasses the freeze for :add and always logs" do
      team = insert(:team)
      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)
      player = insert(:player, region_id: team.region_id)
      admin = insert(:admin)

      assert {:ok, added} = Teams.override_roster_change(:add, team, player, admin)
      assert added.team_id == team.id

      assert Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
               entity_id: player.id,
               action_type: "override_roster_add"
             )
    end

    test "override_roster_change/4 bypasses the freeze for :remove and always logs" do
      team = insert(:team)
      {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)
      admin = insert(:admin)

      assert {:ok, removed} = Teams.override_roster_change(:remove, team, member, admin)
      assert is_nil(removed.team_id)

      assert Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
               entity_id: member.id,
               action_type: "override_roster_remove"
             )
    end

    test "override_roster_change/4 still enforces the roster-size cap" do
      team = insert(:team)
      Teams.lock_roster(team.id)

      for _ <- 1..8 do
        team = Repo.get!(Cuevolution.Teams.Team, team.id)

        Teams.override_roster_change(
          :add,
          team,
          insert(:player, region_id: team.region_id),
          insert(:admin)
        )
      end

      team = Repo.get!(Cuevolution.Teams.Team, team.id)
      admin = insert(:admin)
      ninth_player = insert(:player, region_id: team.region_id)

      assert {:error, :roster_full} =
               Teams.override_roster_change(:add, team, ninth_player, admin)
    end

    test "is triggered the moment the team is drawn into a group — before any fixture or result exists" do
      region = build(:region)
      team = insert(:team, region_id: region.id)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "team",
          name: "Pool A"
        })

      participation =
        insert(:stage_participation,
          player_id: nil,
          team_id: team.id,
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "team"
        )

      assert {:ok, _membership} = Competitions.assign_to_group(participation, group)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)

      assert {:error, :roster_frozen} =
               Teams.invite_player(team, insert(:player, region_id: team.region_id))

      assert {:error, :roster_frozen} =
               Teams.remove_player_from_roster(team, insert(:player, region_id: team.region_id))
    end
  end

  describe "delete_team/2" do
    test "releases the roster, cancels pending invitations, and removes the team" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Doomed Team"})
      captain = Repo.get!(Player, captain.id)
      {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      assert :ok = Teams.delete_team(team, captain)

      refute Repo.get!(Player, captain.id).team_id
      refute Repo.get!(Player, member.id).team_id
      refute Repo.get(Cuevolution.Teams.TeamInvitation, invitation.id)
      refute Repo.get(Cuevolution.Teams.Team, team.id)
    end

    test "rejects once the roster is frozen" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      captain = Repo.get!(Player, captain.id)
      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)

      assert {:error, :roster_frozen} = Teams.delete_team(team, captain)
      assert Repo.get(Cuevolution.Teams.Team, team.id)
    end

    test "rejects if the acting player isn't the team's captain" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      impostor = insert(:player)

      assert {:error, :not_captain} = Teams.delete_team(team, impostor)
      assert Repo.get(Cuevolution.Teams.Team, team.id)
    end
  end

  describe "invite_player/2" do
    test "creates a pending invitation, dispatches a notification, and schedules expiry" do
      team = insert(:team)
      invitee = insert(:player, notification_preference: "email")

      assert {:ok, invitation} = Teams.invite_player(team, invitee)
      assert invitation.status == "pending"
      assert invitation.team_id == team.id
      assert invitation.player_id == invitee.id
      refute Repo.get!(Player, invitee.id).team_id

      notification =
        Repo.get_by!(Cuevolution.Notifications.Notification,
          player_id: invitee.id,
          event_type: "team_invitation"
        )

      assert notification.payload["team_name"] == team.name

      assert_enqueued(
        worker: Cuevolution.Teams.Workers.ExpireTeamInvitationWorker,
        args: %{"invitation_id" => invitation.id}
      )
    end

    test "allows inviting a player from a different region than the team's (no such restriction exists)" do
      region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

      team = insert(:team, region_id: region_a.id)
      invitee = insert(:player, region_id: region_b.id)

      assert {:ok, _invitation} = Teams.invite_player(team, invitee)
    end

    test "rejects inviting a player already on a team" do
      captain_a = insert(:player)
      {:ok, team_a} = Teams.create_team(captain_a, %{"name" => "Team A"})
      team_b = insert(:team)
      member_of_a = Repo.get!(Player, captain_a.id)

      assert {:error, :already_on_a_team} = Teams.invite_player(team_b, member_of_a)
      assert Repo.get!(Player, member_of_a.id).team_id == team_a.id
    end

    test "rejects a duplicate pending invitation to the same player from the same team" do
      team = insert(:team)
      invitee = insert(:player)

      assert {:ok, _invitation} = Teams.invite_player(team, invitee)
      assert {:error, :invitation_already_pending} = Teams.invite_player(team, invitee)
    end

    test "rejects once the roster is frozen" do
      team = insert(:team)
      Teams.lock_roster(team.id)
      team = Repo.get!(Cuevolution.Teams.Team, team.id)

      assert {:error, :roster_frozen} = Teams.invite_player(team, insert(:player))
    end

    test "rejects once the roster is at the 8-player maximum" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Full Team"})

      for _ <- 1..7 do
        Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      end

      assert {:error, :roster_full} = Teams.invite_player(team, insert(:player))
    end
  end

  describe "accept_invitation/2" do
    test "adds the player to the roster and marks the invitation accepted" do
      team = insert(:team)
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      assert {:ok, updated_player} = Teams.accept_invitation(invitation, invitee)
      assert updated_player.team_id == team.id

      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "accepted"
    end

    test "auto-cancels the player's other pending invitations" do
      invitee = insert(:player)
      team_a = insert(:team)
      team_b = insert(:team)
      {:ok, invitation_a} = Teams.invite_player(team_a, invitee)
      {:ok, invitation_b} = Teams.invite_player(team_b, invitee)

      assert {:ok, _player} = Teams.accept_invitation(invitation_a, invitee)

      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation_a.id).status == "accepted"
      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation_b.id).status == "cancelled"
    end

    test "rejects an expired invitation" do
      team = insert(:team)
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      invitation
      |> Ecto.Changeset.change(expires_at: past)
      |> Repo.update!()

      assert {:error, :expired} = Teams.accept_invitation(invitation, invitee)
      refute Repo.get!(Player, invitee.id).team_id
    end

    test "rejects if the roster filled up before the invitation was accepted" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Almost Full"})
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      for _ <- 1..7 do
        Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
      end

      team = Repo.get!(Cuevolution.Teams.Team, team.id)
      assert {:error, :roster_full} = Teams.accept_invitation(invitation, invitee)
      refute team.id == Repo.get!(Player, invitee.id).team_id
    end
  end

  describe "decline_invitation/2" do
    test "marks the invitation declined without touching the roster" do
      team = insert(:team)
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      assert {:ok, _invitation} = Teams.decline_invitation(invitation, invitee)

      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "declined"
      refute Repo.get!(Player, invitee.id).team_id
    end
  end

  describe "cancel_invitation/2" do
    test "the captain can cancel a pending invitation" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      captain = Repo.get!(Player, captain.id)
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)

      assert {:ok, _invitation} = Teams.cancel_invitation(invitation, captain)
      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "cancelled"
    end

    test "rejects if the acting player isn't the team's captain" do
      captain = insert(:player)
      {:ok, team} = Teams.create_team(captain, %{"name" => "Team"})
      invitee = insert(:player)
      {:ok, invitation} = Teams.invite_player(team, invitee)
      impostor = insert(:player)

      assert {:error, :not_captain} = Teams.cancel_invitation(invitation, impostor)
      assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "pending"
    end
  end

  describe "list_teams_filtered/1" do
    test "with no filters, returns all teams" do
      insert_list(3, :team)

      assert length(Teams.list_teams_filtered()) == 3
    end

    test "filters by region_id" do
      region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

      captain_a = insert(:player, region_id: region_a.id)
      captain_b = insert(:player, region_id: region_b.id)
      team_a = insert(:team, region_id: region_a.id, captain_id: captain_a.id)
      _team_b = insert(:team, region_id: region_b.id, captain_id: captain_b.id)

      results = Teams.list_teams_filtered(%{region_id: region_a.id})

      assert [found] = results
      assert found.id == team_a.id
    end

    test "filters by name substring, case-insensitively" do
      target = insert(:team, name: "Westlands Cue Kings")
      _other = insert(:team, name: "Rift Valley Racks")

      results = Teams.list_teams_filtered(%{name: "westlands"})

      assert [found] = results
      assert found.id == target.id
    end

    test "filters by stage_id via an indexed query, without loading every participation" do
      stage_a = build(:stage)
      stage_b = build(:stage)
      team_in_a = insert(:team)
      team_in_b = insert(:team)

      insert(:stage_participation,
        player_id: nil,
        team_id: team_in_a.id,
        category: "team",
        stage_id: stage_a.id
      )

      insert(:stage_participation,
        player_id: nil,
        team_id: team_in_b.id,
        category: "team",
        stage_id: stage_b.id
      )

      results = Teams.list_teams_filtered(%{stage_id: stage_a.id})

      assert [found] = results
      assert found.id == team_in_a.id
    end
  end
end
