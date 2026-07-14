defmodule CuevolutionWeb.PageControllerTest do
  use CuevolutionWeb.ConnCase

  alias Cuevolution.Accounts

  test "GET / renders the landing page for anonymous visitors", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Register to play"
  end

  test "GET / redirects logged-in players to fixtures", %{conn: conn} do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:player_token, token)
      |> get(~p"/")

    assert redirected_to(conn) == ~p"/fixtures"
  end
end
