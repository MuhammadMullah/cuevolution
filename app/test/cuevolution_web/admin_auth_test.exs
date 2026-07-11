defmodule CuevolutionWeb.AdminAuthTest do
  use CuevolutionWeb.ConnCase, async: true

  alias Cuevolution.Accounts
  alias CuevolutionWeb.AdminAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, CuevolutionWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])

    %{conn: conn}
  end

  defp socket_with_flash do
    %Phoenix.LiveView.Socket{
      endpoint: CuevolutionWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end

  describe "fetch_current_admin/2 + require_admin/2" do
    test "anonymous request: no current_admin assigned, require_admin redirects", %{conn: conn} do
      conn = AdminAuth.fetch_current_admin(conn, [])
      assert conn.assigns.current_admin == nil

      conn = AdminAuth.require_admin(conn, [])
      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "player-session request: player token doesn't grant admin access", %{conn: conn} do
      conn =
        conn
        |> put_session(:player_token, "some-opaque-player-session-token")
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin == nil

      conn = AdminAuth.require_admin(conn, [])
      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "admin-session request: current_admin assigned, require_admin passes through", %{
      conn: conn
    } do
      admin = insert(:admin)
      admin_token = Accounts.generate_admin_session_token(admin)

      conn =
        conn
        |> put_session(:admin_token, admin_token)
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin.id == admin.id

      conn = AdminAuth.require_admin(conn, [])
      refute conn.halted
    end
  end

  describe "on_mount :ensure_admin" do
    test "anonymous session halts and redirects" do
      socket = socket_with_flash()

      assert {:halt, _socket} = AdminAuth.on_mount(:ensure_admin, %{}, %{}, socket)
    end

    test "player-session session halts and redirects" do
      socket = socket_with_flash()

      assert {:halt, _socket} =
               AdminAuth.on_mount(
                 :ensure_admin,
                 %{},
                 %{"player_token" => "some-opaque-player-session-token"},
                 socket
               )
    end

    test "admin-session session continues with current_admin assigned" do
      admin = insert(:admin)
      admin_token = Accounts.generate_admin_session_token(admin)
      socket = socket_with_flash()

      assert {:cont, socket} =
               AdminAuth.on_mount(:ensure_admin, %{}, %{"admin_token" => admin_token}, socket)

      assert socket.assigns.current_admin.id == admin.id
    end
  end
end
