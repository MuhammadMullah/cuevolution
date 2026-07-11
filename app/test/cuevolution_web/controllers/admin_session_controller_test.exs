defmodule CuevolutionWeb.AdminSessionControllerTest do
  use CuevolutionWeb.ConnCase, async: true

  alias Cuevolution.Accounts

  setup do
    %{admin: insert(:admin, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))}
  end

  describe "POST /admin/login" do
    test "logs the admin in and redirects to the dashboard on valid credentials", %{
      conn: conn,
      admin: admin
    } do
      conn =
        post(conn, ~p"/admin/login", %{
          "admin" => %{"email" => admin.email, "password" => "correct_password"}
        })

      assert redirected_to(conn) == ~p"/admin/dashboard"
      assert get_session(conn, :admin_token)
    end

    test "redirects back to login with a flash error on invalid credentials", %{
      conn: conn,
      admin: admin
    } do
      conn =
        post(conn, ~p"/admin/login", %{
          "admin" => %{"email" => admin.email, "password" => "wrong_password"}
        })

      assert redirected_to(conn) == ~p"/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute get_session(conn, :admin_token)
    end
  end

  describe "DELETE /admin/logout" do
    test "invalidates the session token and redirects", %{conn: conn, admin: admin} do
      token = Accounts.generate_admin_session_token(admin)
      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

      conn = delete(conn, ~p"/admin/logout")

      assert redirected_to(conn) == ~p"/admin/login"
      refute get_session(conn, :admin_token)
      assert Accounts.get_admin_by_session_token(token) == nil
    end
  end
end
