defmodule CuevolutionWeb.TeamDetailLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Teams

  defp log_in_admin(conn) do
    admin = insert(:admin)
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
end
