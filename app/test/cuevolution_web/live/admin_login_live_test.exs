defmodule CuevolutionWeb.AdminLoginLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the admin login form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/login")
    assert html =~ "Admin Login"
  end
end
