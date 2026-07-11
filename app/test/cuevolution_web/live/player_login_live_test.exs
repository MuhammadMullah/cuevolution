defmodule CuevolutionWeb.PlayerLoginLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the sign-in form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/login")
    assert html =~ "Welcome back"
    assert html =~ "Email or username"
  end

  test "links to registration", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/login")
    assert view |> element("a", "Create an account") |> render() =~ ~p"/register"
  end

  test "shows an error flash after a failed sign-in attempt", %{conn: conn} do
    player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

    conn =
      post(conn, ~p"/login", %{
        "player" => %{"login" => player.email, "password" => "wrong_password"}
      })

    assert redirected_to(conn) == ~p"/login"

    conn = get(conn, ~p"/login")
    html = html_response(conn, 200)
    assert html =~ "Invalid email/username or password"
    assert html =~ "AutoDismissFlash"
  end
end
