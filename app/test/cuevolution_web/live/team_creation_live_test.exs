defmodule CuevolutionWeb.TeamCreationLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Repo

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/team/new")
  end

  test "redirects a player who already has a team to the dashboard", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "Existing Team"})
    captain = Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    assert {:error, {:live_redirect, %{to: "/team"}}} = live(conn, ~p"/team/new")
  end

  test "creates a team and becomes captain", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/team/new")

    {:error, {:live_redirect, %{to: "/team"}}} =
      view
      |> form("form", team: %{"name" => "The Sharks"})
      |> render_submit()

    assert Repo.get!(Cuevolution.Accounts.Player, player.id).team_id
  end
end
