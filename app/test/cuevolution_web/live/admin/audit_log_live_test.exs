defmodule CuevolutionWeb.Admin.AuditLogLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/audit-log")
  end

  for role <- ["tournament_director", "regional_coordinator", "venue_representative"] do
    test "redirects a #{role} to the dashboard, even though they held view_directory before",
         %{conn: conn} do
      conn = log_in_admin(conn, insert(:admin, role: unquote(role)))

      assert {:error, {:redirect, %{to: "/admin/dashboard"}}} = live(conn, ~p"/admin/audit-log")
    end
  end

  test "a super admin can open the audit log", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, _view, html} = live(conn, ~p"/admin/audit-log")

    assert html =~ "Audit log"
  end

  test "only super admins see the Audit Log nav link", %{conn: conn} do
    super_admin = insert(:admin, role: "super_admin")
    director = insert(:admin, role: "tournament_director")

    {:ok, _view, html} = live(log_in_admin(conn, super_admin), ~p"/admin/dashboard")
    assert html =~ ~s(href="/admin/audit-log")

    {:ok, _view, html} = live(log_in_admin(conn, director), ~p"/admin/dashboard")
    refute html =~ ~s(href="/admin/audit-log")
  end

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end
end
