defmodule CuevolutionWeb.AdminResultsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/results")
  end

  test "shows the Unplayed/Played tabs, both always empty", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Match results"
    assert html =~ "No fixtures in this list."

    html = view |> element("button", "Played / Correct") |> render_click()
    assert html =~ "No fixtures in this list."
  end
end
