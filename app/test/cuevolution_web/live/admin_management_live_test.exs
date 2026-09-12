defmodule CuevolutionWeb.AdminManagementLiveTest do
  use CuevolutionWeb.ConnCase, async: true
  use Oban.Testing, repo: Cuevolution.Repo

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/admins")
  end

  test "redirects non-super-admins to the dashboard", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "tournament_manager"))

    assert {:error, {:redirect, %{to: "/admin/dashboard"}}} = live(conn, ~p"/admin/admins")
  end

  test "super admins see the invite form and existing admins", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    existing = insert(:admin, role: "venue_representative")

    {:ok, _view, html} = live(conn, ~p"/admin/admins")

    assert html =~ "Invite an admin"
    assert html =~ existing.email
    assert html =~ "Venue Representative"
  end

  test "inviting an admin creates a pending record and enqueues the setup email", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html =
      view
      |> form("#invite-admin-form", %{
        "admin" => %{"email" => "manager@cuevolution.test", "role" => "tournament_manager"}
      })
      |> render_submit()

    assert html =~ "Invitation sent to manager@cuevolution.test as Tournament Manager."
    assert html =~ "manager@cuevolution.test"
    assert html =~ "Invited"

    assert_enqueued(worker: Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker)
  end

  test "shows validation errors for an invalid invite", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html =
      view
      |> form("#invite-admin-form", %{"admin" => %{"email" => "not-an-email", "role" => ""}})
      |> render_change()

    assert html =~ "must have the @ sign"
  end

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end
end
