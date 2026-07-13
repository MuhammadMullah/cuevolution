defmodule CuevolutionWeb.AdminDrawsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/draws")
  end

  test "shows the fixture-entry shell, adds a row, and saving explains nothing is wired up yet",
       %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/draws")

    assert html =~ "Fixture entry"
    assert html =~ "No rounds scheduled yet"
    assert html =~ "No fixtures entered for this round yet"

    html = view |> element("button", "+ Add row") |> render_click()
    assert Regex.scan(~r/Search name…/, html) |> length() == 4

    html = view |> element("button", "Save round & notify players") |> render_click()
    assert html =~ "connected to a scheduling system yet"
  end
end
