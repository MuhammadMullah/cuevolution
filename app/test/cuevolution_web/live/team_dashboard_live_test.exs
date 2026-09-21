defmodule CuevolutionWeb.TeamDashboardLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/team")
  end

  test "redirects a player with no team to team creation", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    assert {:error, {:live_redirect, %{to: "/team/new"}}} = live(conn, ~p"/team")
  end

  test "shows team info and roster to a member", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/team")

    assert html =~ "The Sharks"
    assert html =~ captain.username
    assert html =~ ">1</span>"
    assert html =~ "/ 8"
  end

  test "the captain can rename the team from the team header", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    assert has_element?(view, "button[aria-label='Edit team name']")

    view
    |> element("button[phx-click=edit_team_name]")
    |> render_click()

    assert has_element?(view, "#team-name-form")

    view
    |> form("#team-name-form", team: %{"name" => "The Great Sharks"})
    |> render_submit()

    assert has_element?(view, "h1", "The Great Sharks")
    assert Repo.get!(Cuevolution.Teams.Team, team.id).name == "The Great Sharks"
  end

  test "the captain can update the team match location after the draw", %{conn: conn} do
    captain = insert(:player, inserted_at: ~N[2026-09-19 00:00:00])
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    region = build(:region)
    venue = insert(:venue, region_id: region.id)
    {1, _} = Teams.lock_roster(team.id)
    captain = Repo.get!(Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    view
    |> form("#team-location-form")
    |> render_change(team_location: %{"match_region_id" => region.id, "match_venue_id" => ""})

    assert has_element?(view, "#team-location-venue option[value='#{venue.id}']")

    view
    |> form("#team-location-form")
    |> render_submit(
      team_location: %{"match_region_id" => region.id, "match_venue_id" => venue.id}
    )

    saved_team = Repo.get!(Cuevolution.Teams.Team, team.id)
    assert saved_team.match_region_id == region.id
    assert saved_team.match_venue_id == venue.id
  end

  test "a non-captain cannot edit the team name", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    member = Repo.get!(Player, member.id)

    conn = log_in_player(conn, member)
    {:ok, view, _html} = live(conn, ~p"/team")

    refute has_element?(view, "button[aria-label='Edit team name']")

    html = render_click(view, "edit_team_name", %{})

    assert html =~ "Only the captain can update the team name."
    assert Repo.get!(Cuevolution.Teams.Team, team.id).name == "The Sharks"
  end

  test "the captain invites a registered player by username, who is not yet on the roster",
       %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    recruit = insert(:player, username: "recruitable")

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      view
      |> form("form", roster: %{"username" => "recruitable"})
      |> render_submit()

    assert html =~ "Invitation sent to @recruitable"
    assert html =~ "recruitable"
    refute Repo.get!(Player, recruit.id).team_id

    assert [invitation] = Teams.list_pending_invitations_for_team(team.id)
    assert invitation.player_id == recruit.id
    assert invitation.status == "pending"
  end

  test "the captain can search by player name and select an autocomplete suggestion", %{
    conn: conn
  } do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    recruit = insert(:player, first_name: "Ada", last_name: "Lovelace", username: "adal")

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    view
    |> element("#add-player-form")
    |> render_change(roster: %{"username" => "Lovelace"})

    assert has_element?(view, "#player-suggestion-#{recruit.id}")
    assert has_element?(view, "#player-suggestions", "Ada Lovelace")

    view
    |> element("#player-suggestion-#{recruit.id}")
    |> render_click()

    html = view |> element("#add-player-form") |> render_submit()

    assert html =~ "Invitation sent to @adal"
    assert [%{player_id: player_id}] = Teams.list_pending_invitations_for_team(team.id)
    assert player_id == recruit.id
  end

  test "the invited player accepts and joins the roster; other pending invites are cancelled",
       %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    recruit = insert(:player, username: "recruitable")

    {:ok, invitation} = Teams.invite_player(team, recruit)

    other_captain = insert(:player)
    {:ok, other_team} = Teams.create_team(other_captain, %{"name" => "The Minnows"})
    {:ok, other_invitation} = Teams.invite_player(other_team, recruit)

    conn = log_in_player(conn, recruit)
    {:ok, view, html} = live(conn, ~p"/fixtures")

    assert html =~ "The Sharks"
    assert html =~ "The Minnows"

    {:error, {:live_redirect, %{to: "/team"}}} =
      view
      |> element("button[phx-click=accept_invitation][phx-value-id='#{invitation.id}']")
      |> render_click()

    assert Repo.get!(Player, recruit.id).team_id == team.id
    assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "accepted"
    assert Repo.get!(Cuevolution.Teams.TeamInvitation, other_invitation.id).status == "cancelled"
  end

  test "the invited player can decline an invitation", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    recruit = insert(:player, username: "recruitable")
    {:ok, invitation} = Teams.invite_player(team, recruit)

    conn = log_in_player(conn, recruit)
    {:ok, view, _html} = live(conn, ~p"/fixtures")

    html =
      view
      |> element("button[phx-click=decline_invitation][phx-value-id='#{invitation.id}']")
      |> render_click()

    assert html =~ "Invitation declined"
    refute Repo.get!(Player, recruit.id).team_id
    assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "declined"
  end

  test "the captain can cancel a pending invitation", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    recruit = insert(:player, username: "recruitable")
    {:ok, invitation} = Teams.invite_player(team, recruit)

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      view
      |> element("button[phx-click=cancel_invitation][phx-value-id='#{invitation.id}']")
      |> render_click()

    assert html =~ "Invitation cancelled"
    assert Repo.get!(Cuevolution.Teams.TeamInvitation, invitation.id).status == "cancelled"
  end

  test "a non-captain cannot invite a player even by forging the event", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    member = Repo.get!(Player, member.id)
    recruit = insert(:player, username: "recruitable")

    conn = log_in_player(conn, member)
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      render_click(view, "add_player", %{"roster" => %{"username" => "recruitable"}})

    assert html =~ "Only the captain can invite players."
    refute Repo.get!(Player, recruit.id).team_id
  end

  test "the captain can remove a player from the roster", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    view
    |> element("button[phx-click=remove_player][phx-value-id='#{member.id}']")
    |> render_click()

    refute Repo.get!(Player, member.id).team_id
  end

  test "a non-captain roster member does not see remove/add controls", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    teammate = insert(:player, region_id: team.region_id, username: "teammate")
    {:ok, member} = Teams.add_player_to_roster(team, teammate)
    member = Repo.get!(Player, member.id)

    conn = log_in_player(conn, member)
    {:ok, view, html} = live(conn, ~p"/team")

    assert has_element?(view, "#team-members")
    assert has_element?(view, "#team-member-#{captain.id}", captain.username)
    assert has_element?(view, "#team-member-#{teammate.id}", teammate.username)
    refute html =~ "Invite a player"
    refute has_element?(view, "button[phx-click=remove_player]")
    refute has_element?(view, "button[phx-click=delete_team]")
  end

  test "the captain can delete the team, releasing every member", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    {:error, {:live_redirect, %{to: "/team/new"}}} =
      view
      |> element("button[phx-click=delete_team]")
      |> render_click()

    refute Repo.get!(Player, captain.id).team_id
    refute Repo.get!(Player, member.id).team_id
    refute Repo.get(Cuevolution.Teams.Team, team.id)
  end

  test "delete_team is blocked once the team has been drawn into a group", %{conn: conn} do
    region = build(:region)
    captain = insert(:player, region_id: region.id)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)

    {:ok, group} =
      Cuevolution.Competitions.create_group(%{
        stage_id: Repo.get_by!(Cuevolution.Competitions.Stage, name: "Regional").id,
        region_id: region.id,
        category: "team",
        name: "Pool A"
      })

    participation =
      insert(:stage_participation,
        player_id: nil,
        team_id: team.id,
        stage_id: group.stage_id,
        region_id: region.id,
        category: "team"
      )

    {:ok, _membership} = Cuevolution.Competitions.assign_to_group(participation, group)

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      view
      |> element("button[phx-click=delete_team]")
      |> render_click()

    assert html =~ "already been drawn into a stage"
    assert Repo.get(Cuevolution.Teams.Team, team.id)
  end

  test "a non-captain cannot delete the team even by forging the event", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    member = Repo.get!(Player, member.id)

    conn = log_in_player(conn, member)
    {:ok, view, _html} = live(conn, ~p"/team")

    html = render_click(view, "delete_team", %{})

    assert html =~ "Only the captain can delete the team."
    assert Repo.get(Cuevolution.Teams.Team, team.id)
  end
end
