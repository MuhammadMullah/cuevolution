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

  test "limits repeated requests for the same login, enqueueing nothing further", %{conn: conn} do
    player = insert(:player)

    for _ <- 1..5 do
      {:ok, view, _html} = live(conn, ~p"/forgot-password")
      view |> form("form", forgot: %{"login" => player.email}) |> render_submit()
    end

    {:ok, view, _html} = live(conn, ~p"/forgot-password")
    html = view |> form("form", forgot: %{"login" => player.email}) |> render_submit()

    assert html =~ "Too many reset requests"
    refute html =~ "Check your email"

    assert length(
             all_enqueued(worker: SendPasswordResetEmailWorker, args: %{"player_id" => player.id})
           ) == 5
  end

  test "limits repeated logins that match no account too, so existence isn't revealed", %{
    conn: conn
  } do
    login = "ghost-#{System.unique_integer([:positive])}"

    for _ <- 1..5 do
      {:ok, view, _html} = live(conn, ~p"/forgot-password")
      view |> form("form", forgot: %{"login" => login}) |> render_submit()
    end

    {:ok, view, _html} = live(conn, ~p"/forgot-password")
    html = view |> form("form", forgot: %{"login" => login}) |> render_submit()

    assert html =~ "Too many reset requests"
  end

  test "limit is case-insensitive on the login", %{conn: conn} do
    player = insert(:player)

    for _ <- 1..5 do
      {:ok, view, _html} = live(conn, ~p"/forgot-password")
      view |> form("form", forgot: %{"login" => String.upcase(player.email)}) |> render_submit()
    end

    {:ok, view, _html} = live(conn, ~p"/forgot-password")
    html = view |> form("form", forgot: %{"login" => player.email}) |> render_submit()

    assert html =~ "Too many reset requests"
  end

  test "resend is limited too", %{conn: conn} do
    player = insert(:player)
    {:ok, view, _html} = live(conn, ~p"/forgot-password")
    view |> form("form", forgot: %{"login" => player.email}) |> render_submit()

    for _ <- 1..4, do: view |> element("a", "Resend email") |> render_click()
    html = view |> element("a", "Resend email") |> render_click()

    assert html =~ "Too many reset requests"

    assert length(
             all_enqueued(worker: SendPasswordResetEmailWorker, args: %{"player_id" => player.id})
           ) == 5
  end
end
