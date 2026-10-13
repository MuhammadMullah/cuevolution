defmodule CuevolutionWeb.AdminForgotPasswordLiveTest do
  use CuevolutionWeb.ConnCase, async: true
  use Oban.Testing, repo: Cuevolution.Repo

  import Phoenix.LiveViewTest

  alias Cuevolution.Notifications.Workers.SendAdminPasswordResetEmailWorker

  test "is linked from the admin login page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/login")

    assert view |> element("a", "Forgot your password?") |> render() =~ "/admin/forgot-password"
  end

  test "renders the request form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/forgot-password")
    assert html =~ "Forgot your password?"
  end

  test "enqueues the reset email and shows the confirmation for an active admin", %{conn: conn} do
    admin = insert(:admin)
    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")

    html = view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()

    assert html =~ "Check your email"
    assert_enqueued(worker: SendAdminPasswordResetEmailWorker, args: %{"admin_id" => admin.id})
  end

  test "matches the email case-insensitively", %{conn: conn} do
    admin = insert(:admin)
    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")

    view |> form("form", forgot: %{"email" => String.upcase(admin.email)}) |> render_submit()

    assert_enqueued(worker: SendAdminPasswordResetEmailWorker, args: %{"admin_id" => admin.id})
  end

  test "shows the identical confirmation for an unknown email, enqueueing nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")

    html = view |> form("form", forgot: %{"email" => "nobody@example.com"}) |> render_submit()

    assert html =~ "Check your email"
    refute_enqueued(worker: SendAdminPasswordResetEmailWorker)
  end

  for {label, attrs} <- [
        pending: [hashed_password: nil],
        suspended: [suspended_at: ~U[2026-01-01 00:00:00Z]],
        removed: [removed_at: ~U[2026-01-01 00:00:00Z]]
      ] do
    test "sends nothing for a #{label} admin, with the same confirmation", %{conn: conn} do
      admin = insert(:admin, unquote(Macro.escape(attrs)))
      {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")

      html = view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()

      assert html =~ "Check your email"
      refute_enqueued(worker: SendAdminPasswordResetEmailWorker)
    end
  end

  test "resend enqueues a second email for a matched admin", %{conn: conn} do
    admin = insert(:admin)
    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")

    view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()
    view |> element("a", "Resend email") |> render_click()

    assert [_first, _second] =
             all_enqueued(
               worker: SendAdminPasswordResetEmailWorker,
               args: %{"admin_id" => admin.id}
             )
  end

  test "limits repeated requests for the same email, enqueueing nothing further", %{conn: conn} do
    admin = insert(:admin)

    for _ <- 1..5 do
      {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")
      view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()
    end

    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")
    html = view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()

    assert html =~ "Too many reset requests"
    refute html =~ "Check your email"

    assert length(
             all_enqueued(
               worker: SendAdminPasswordResetEmailWorker,
               args: %{"admin_id" => admin.id}
             )
           ) == 5
  end

  test "limits repeated emails that match no account too, so existence isn't revealed", %{
    conn: conn
  } do
    email = "ghost-#{System.unique_integer([:positive])}@example.com"

    for _ <- 1..5 do
      {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")
      view |> form("form", forgot: %{"email" => email}) |> render_submit()
    end

    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")
    html = view |> form("form", forgot: %{"email" => email}) |> render_submit()

    assert html =~ "Too many reset requests"
  end

  test "resend is limited too", %{conn: conn} do
    admin = insert(:admin)
    {:ok, view, _html} = live(conn, ~p"/admin/forgot-password")
    view |> form("form", forgot: %{"email" => admin.email}) |> render_submit()

    for _ <- 1..4, do: view |> element("a", "Resend email") |> render_click()
    html = view |> element("a", "Resend email") |> render_click()

    assert html =~ "Too many reset requests"

    assert length(
             all_enqueued(
               worker: SendAdminPasswordResetEmailWorker,
               args: %{"admin_id" => admin.id}
             )
           ) == 5
  end
end
