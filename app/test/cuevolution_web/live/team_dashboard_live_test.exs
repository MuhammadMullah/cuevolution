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

  test "the captain can add a registered player to the roster by username", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Player, captain.id)
    recruit = insert(:player, username: "recruitable")

    conn = log_in_player(conn, captain)
    {:ok, view, _html} = live(conn, ~p"/team")

    html =
      view
      |> form("form", roster: %{"username" => "recruitable"})
      |> render_submit()

    assert html =~ "recruitable"
    assert Repo.get!(Player, recruit.id).team_id
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
    {:ok, member} = Teams.add_player_to_roster(team, insert(:player, region_id: team.region_id))
    member = Repo.get!(Player, member.id)

    conn = log_in_player(conn, member)
    {:ok, view, html} = live(conn, ~p"/team")

    refute html =~ "Add a player"
    refute has_element?(view, "button[phx-click=remove_player]")
  end
end
