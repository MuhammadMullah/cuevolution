defmodule CuevolutionWeb.TeamDetailLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.TeamInvitation

  defp log_in_admin(conn, role \\ "super_admin") do
    admin = insert(:admin, role: role)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    team = insert(:team)

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/teams/#{team.id}")
  end

  test "shows the team's details, roster, and eligibility to a logged-in admin", %{conn: conn} do
    captain = insert(:player, first_name: "Cap", last_name: "Tain")
    {:ok, team} = Teams.create_team(captain, %{"name" => "Rift Valley Racks"})

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/teams/#{team.id}")

    assert html =~ "Rift Valley Racks"
    assert html =~ "Cap Tain"
    assert html =~ "Captain"
    assert html =~ "Not eligible yet"
  end

  test "an admin can add a player directly without creating an invitation", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "Rift Valley Racks"})
    recruit = insert(:player, first_name: "Ada", last_name: "Lovelace", username: "adal")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    view
    |> element("#admin-player-search")
    |> render_keyup(%{"value" => "Lovelace"})

    assert has_element?(view, "#admin-player-suggestion-#{recruit.id}")

    view
    |> element("#admin-player-suggestion-#{recruit.id}")
    |> render_click()

    view
    |> element("#admin-add-player-form")
    |> render_submit()

    assert Repo.get!(Player, recruit.id).team_id == team.id

    assert Repo.get_by(TeamInvitation, player_id: recruit.id) == nil
  end

  test "an admin can create a team with a selected captain and roster", %{conn: conn} do
    captain = insert(:player, first_name: "Ada", last_name: "Lovelace", username: "adal")
    teammate = insert(:player, first_name: "Grace", last_name: "Hopper", username: "graceh")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/teams/new")

    render_keyup(view, "search_players", %{"kind" => "captain", "value" => "Ada"})
    view |> element("#captain-suggestion-#{captain.id}") |> render_click()
    render_keyup(view, "search_players", %{"kind" => "player", "value" => "Grace"})
    view |> element("#player-suggestion-#{teammate.id}") |> render_click()

    {:error, {:live_redirect, %{to: path}}} =
      view |> form("#admin-team-form", team: %{"name" => "The Admin Sharks"}) |> render_submit()

    assert path =~ "/admin/teams/"
    assert Repo.get!(Player, captain.id).team_id
    assert Repo.get!(Player, teammate.id).team_id == Repo.get!(Player, captain.id).team_id
  end

  test "an admin can delete a team and release its roster", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Admin Sharks"})
    teammate = insert(:player, region_id: team.region_id)
    {:ok, _teammate} = Teams.add_player_to_roster(team, teammate)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    assert has_element?(view, "#admin-delete-team-button")

    {:error, {:live_redirect, %{to: "/admin/players"}}} =
      view |> element("#admin-delete-team-button") |> render_click()

    assert is_nil(Repo.get(Cuevolution.Teams.Team, team.id))
    assert is_nil(Repo.get!(Player, captain.id).team_id)
    assert is_nil(Repo.get!(Player, teammate.id).team_id)
  end

  test "an admin cannot delete a team once it has been drawn", %{conn: conn} do
    captain = insert(:player)
    {:ok, team} = Teams.create_team(captain, %{"name" => "The Admin Sharks"})
    {1, _} = Teams.lock_roster(team.id)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/teams/#{team.id}")

    html = view |> element("#admin-delete-team-button") |> render_click()

    assert html =~ "can no longer be deleted"
    assert Repo.get(Cuevolution.Teams.Team, team.id)
  end

  test "admins without team-management permission cannot open team management", %{conn: conn} do
    conn = log_in_admin(conn, "venue_representative")
    team = insert(:team)

    assert {:error, {:redirect, %{to: "/admin/dashboard"}}} =
             live(conn, ~p"/admin/teams/#{team.id}")
  end
end
