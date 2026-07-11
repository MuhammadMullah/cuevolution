defmodule CuevolutionWeb.PlayerDetailLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    player = insert(:player)

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/players/#{player.id}")
  end

  test "shows the player's profile details to a logged-in admin", %{conn: conn} do
    player = insert(:player, first_name: "Detail", last_name: "Test Player")

    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

    {:ok, _view, html} = live(conn, ~p"/admin/players/#{player.id}")

    assert html =~ "Detail Test Player"
    assert html =~ player.username
    assert html =~ player.email
  end
end
