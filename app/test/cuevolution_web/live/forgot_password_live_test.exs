defmodule CuevolutionWeb.ForgotPasswordLiveTest do
  use CuevolutionWeb.ConnCase, async: true
  use Oban.Testing, repo: Cuevolution.Repo

  import Phoenix.LiveViewTest

  alias Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker

  test "renders the request form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/forgot-password")
    assert html =~ "Forgot your password?"
  end

  test "rejects a blank submission inline, without transitioning stages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    html = view |> form("form", forgot: %{"login" => ""}) |> render_submit()

    assert html =~ "Enter your email or username to continue."
    refute html =~ "Check your email"
  end

  test "shows the same confirmation for an existing login, and enqueues the reset email", %{
    conn: conn
  } do
    player = insert(:player)
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    html = view |> form("form", forgot: %{"login" => player.email}) |> render_submit()

    assert html =~ "Check your email"
    assert_enqueued(worker: SendPasswordResetEmailWorker, args: %{"player_id" => player.id})
  end

  test "shows the identical confirmation for a login matching no account, enqueueing nothing", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    html = view |> form("form", forgot: %{"login" => "nobody-at-all"}) |> render_submit()

    assert html =~ "Check your email"
    refute_enqueued(worker: SendPasswordResetEmailWorker)
  end

  test "resend re-attempts delivery for a matched login", %{conn: conn} do
    player = insert(:player)
    {:ok, view, _html} = live(conn, ~p"/forgot-password")

    view |> form("form", forgot: %{"login" => player.email}) |> render_submit()
    assert_enqueued(worker: SendPasswordResetEmailWorker, args: %{"player_id" => player.id})

    view |> element("a", "Resend email") |> render_click()

    assert [_first, _second] =
             all_enqueued(worker: SendPasswordResetEmailWorker, args: %{"player_id" => player.id})
  end
end
