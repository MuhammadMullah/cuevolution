defmodule CuevolutionWeb.PlayerSessionControllerTest do
  use CuevolutionWeb.ConnCase, async: true

  alias Cuevolution.Accounts

  setup do
    %{player: insert(:player, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))}
  end

  describe "POST /login" do
    test "logs the player in by email and redirects to fixtures on valid credentials", %{
      conn: conn,
      player: player
    } do
      conn =
        post(conn, ~p"/login", %{
          "player" => %{"login" => player.email, "password" => "correct_password"}
        })

      assert redirected_to(conn) == ~p"/fixtures"
      assert get_session(conn, :player_token)
    end

    test "logs the player in by username", %{conn: conn, player: player} do
      conn =
        post(conn, ~p"/login", %{
          "player" => %{"login" => player.username, "password" => "correct_password"}
        })

      assert redirected_to(conn) == ~p"/fixtures"
      assert get_session(conn, :player_token)
    end

    test "redirects back to login with a flash error on invalid credentials", %{
      conn: conn,
      player: player
    } do
      conn =
        post(conn, ~p"/login", %{
          "player" => %{"login" => player.email, "password" => "wrong_password"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute get_session(conn, :player_token)
    end
  end

  describe "DELETE /logout" do
    test "invalidates the session token and redirects", %{conn: conn, player: player} do
      token = Accounts.generate_player_session_token(player)
      conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

      conn = delete(conn, ~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :player_token)
      assert Accounts.get_player_by_session_token(token) == nil
    end
  end
end
