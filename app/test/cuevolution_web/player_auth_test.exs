defmodule CuevolutionWeb.PlayerAuthTest do
  use CuevolutionWeb.ConnCase, async: true

  alias Cuevolution.Accounts
  alias CuevolutionWeb.PlayerAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, CuevolutionWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])

    %{conn: conn}
  end

  describe "fetch_current_player/2 + require_player/2" do
    test "anonymous request: no current_player assigned, require_player redirects", %{conn: conn} do
      conn = PlayerAuth.fetch_current_player(conn, [])
      assert conn.assigns.current_player == nil

      conn = PlayerAuth.require_player(conn, [])
      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
    end

    test "admin-session request: admin token doesn't grant player access", %{conn: conn} do
      conn =
        conn
        |> put_session(:admin_token, "some-opaque-admin-session-token")
        |> PlayerAuth.fetch_current_player([])

      assert conn.assigns.current_player == nil
    end

    test "player-session request: current_player assigned, require_player passes through", %{
      conn: conn
    } do
      player = insert(:player)
      token = Accounts.generate_player_session_token(player)

      conn =
        conn
        |> put_session(:player_token, token)
        |> PlayerAuth.fetch_current_player([])

      assert conn.assigns.current_player.id == player.id

      conn = PlayerAuth.require_player(conn, [])
      refute conn.halted
    end
  end
end
