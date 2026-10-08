defmodule CuevolutionWeb.AdminManagementLiveTest do
  use CuevolutionWeb.ConnCase, async: true
  use Oban.Testing, repo: Cuevolution.Repo

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/admins")
  end

  test "redirects admins without user-management permission to the dashboard", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "regional_coordinator"))

    assert {:error, {:redirect, %{to: "/admin/dashboard"}}} = live(conn, ~p"/admin/admins")
  end

  test "super admins see the Add User button and existing admins", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    existing = insert(:admin, role: "venue_representative")

    {:ok, _view, html} = live(conn, ~p"/admin/admins")

    assert html =~ "Add User"
    assert html =~ existing.email
    assert html =~ "Venue Representative"
  end

  test "tournament directors cannot manage super admins", %{conn: conn} do
    director = insert(:admin, role: "tournament_director")
    super_admin = insert(:admin, role: "super_admin", email: "super@cuevolution.test")
    conn = log_in_admin(conn, director)

    {:ok, _view, html} = live(conn, ~p"/admin/admins")

    assert html =~ "Protected — Super Admin accounts cannot be managed by Tournament Directors."
    assert html =~ "disabled"
    refute html =~ ~s(phx-click="toggle_suspend" phx-value-id="#{super_admin.id}")
    refute html =~ ~s(phx-click="remove" phx-value-id="#{super_admin.id}")
  end

  test "inviting an admin creates a pending record and enqueues the setup email", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view |> element("button", "Add User") |> render_click()

    html =
      view
      |> form("#invite-admin-form", %{
        "admin" => %{"email" => "manager@cuevolution.test", "role" => "tournament_director"}
      })
      |> render_submit()

    assert html =~ "Invitation sent to manager@cuevolution.test as Tournament Director."
    assert html =~ "manager@cuevolution.test"
    refute html =~ "invite-admin-form"

    row_html = view |> element("tr", "manager@cuevolution.test") |> render()
    assert row_html =~ "Invited"

    assert_enqueued(worker: Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker)
  end

  test "shows validation errors for an invalid invite", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view |> element("button", "Add User") |> render_click()

    html =
      view
      |> form("#invite-admin-form", %{"admin" => %{"email" => "not-an-email", "role" => ""}})
      |> render_change()

    assert html =~ "must have the @ sign"
  end

  test "selecting venue representative reveals a region filter that narrows the venue list",
       %{conn: conn} do
    [region_a, region_b | _] = Cuevolution.Accounts.list_regions()
    venue_a = insert(:venue, region_id: region_a.id, name: "Region A Venue")
    venue_b = insert(:venue, region_id: region_b.id, name: "Region B Venue")
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view |> element("button", "Add User") |> render_click()

    html_before =
      view
      |> form("#invite-admin-form", %{"admin" => %{"role" => "tournament_director"}})
      |> render_change()

    refute html_before =~ "invite-venue-region-filter"

    view
    |> form("#invite-admin-form", %{"admin" => %{"role" => "venue_representative"}})
    |> render_change()

    html =
      view
      |> form("#invite-admin-form", %{"venue_region_filter" => region_a.id})
      |> render_change()

    assert html =~ venue_a.name
    refute html =~ venue_b.name
  end

  test "region picked for a venue rep invite does not get submitted as the admin's region_id",
       %{conn: conn} do
    region = hd(Cuevolution.Accounts.list_regions())
    venue = insert(:venue, region_id: region.id)
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view |> element("button", "Add User") |> render_click()

    view
    |> form("#invite-admin-form", %{"admin" => %{"role" => "venue_representative"}})
    |> render_change()

    view
    |> form("#invite-admin-form", %{"venue_region_filter" => region.id})
    |> render_change()

    html =
      view
      |> form("#invite-admin-form", %{
        "admin" => %{
          "email" => "venuerep@cuevolution.test",
          "role" => "venue_representative",
          "venue_id" => venue.id
        }
      })
      |> render_submit()

    assert html =~ "Invitation sent to venuerep@cuevolution.test"
    refute html =~ "is only used for regional coordinators"
  end

  test "revoking a pending invite marks it revoked and invalidates its setup link", %{
    conn: conn
  } do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    pending = insert(:admin, hashed_password: nil, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html = view |> element("button", "Revoke invite") |> render_click()

    assert html =~ "Invite for #{pending.email} revoked."
    refute html =~ "Revoke invite"
    assert html =~ "Resend invite"

    row_html = view |> element("tr", pending.email) |> render()
    assert row_html =~ "Invite revoked"
  end

  test "resending a revoked invite clears the badge and enqueues a fresh email", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    revoked =
      insert(:admin,
        hashed_password: nil,
        role: "venue_representative",
        invite_revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html = view |> element("button", "Resend invite") |> render_click()

    assert html =~ "Invite resent to #{revoked.email}."

    row_html = view |> element("tr", revoked.email) |> render()
    assert row_html =~ "Invited"
    refute row_html =~ "Invite revoked"

    assert_enqueued(
      worker: Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker,
      args: %{"admin_id" => revoked.id}
    )
  end

  test "filters the list by status", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))

    suspended =
      insert(:admin,
        role: "venue_representative",
        suspended_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    active = insert(:admin, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html =
      view
      |> form("#admin-filter-form", %{"filter" => %{"status" => "suspended"}})
      |> render_change()

    assert html =~ suspended.email
    refute html =~ active.email
  end

  test "filters the list by role", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    coordinator = insert(:admin, role: "regional_coordinator")
    rep = insert(:admin, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html =
      view
      |> form("#admin-filter-form", %{"filter" => %{"role" => "regional_coordinator"}})
      |> render_change()

    assert html =~ coordinator.email
    refute html =~ rep.email
  end

  test "searches the list by mobile number, venue name, or email", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    venue = insert(:venue, name: "Gee spot")

    by_phone =
      insert(:admin, role: "venue_representative", mobile_number: "+254712999184")

    by_venue = insert(:admin, role: "venue_representative", venue_id: venue.id)
    by_email = insert(:admin, email: "findme-by-email@cuevolution.test")
    unrelated = insert(:admin, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    html =
      view
      |> form("#admin-search-form", %{"search" => %{"term" => "999184"}})
      |> render_change()

    assert html =~ by_phone.email
    refute html =~ unrelated.email

    html =
      view
      |> form("#admin-search-form", %{"search" => %{"term" => "gee"}})
      |> render_change()

    assert html =~ by_venue.email
    refute html =~ unrelated.email

    html =
      view
      |> form("#admin-search-form", %{"search" => %{"term" => "findme-by-email"}})
      |> render_change()

    assert html =~ by_email.email
    refute html =~ unrelated.email
  end

  test "clearing the search box restores the full list", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    rep = insert(:admin, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view
    |> form("#admin-search-form", %{"search" => %{"term" => "no-such-term"}})
    |> render_change()

    html = view |> element("button[phx-click='clear_search']") |> render_click()

    assert html =~ rep.email
  end

  test "clearing filters restores the full list", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    rep = insert(:admin, role: "venue_representative")

    {:ok, view, _html} = live(conn, ~p"/admin/admins")

    view
    |> form("#admin-filter-form", %{"filter" => %{"role" => "regional_coordinator"}})
    |> render_change()

    html = view |> element("button", "Clear filters") |> render_click()

    assert html =~ rep.email
  end

  test "paginates the admin list", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "super_admin"))
    for _ <- 1..12, do: insert(:admin, role: "venue_representative")

    {:ok, view, html} = live(conn, ~p"/admin/admins")

    assert html =~ "Page 1 of 2"

    html = view |> element("#admins-next-page") |> render_click()

    assert html =~ "Page 2 of 2"
    assert html =~ "Showing 3 of 13 admins"
  end

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end
end
