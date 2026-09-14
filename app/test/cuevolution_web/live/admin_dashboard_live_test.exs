defmodule CuevolutionWeb.AdminDashboardLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/dashboard")
  end

  test "logged-in admins see the dashboard with their email", %{conn: conn} do
    admin = insert(:admin)
    insert(:player)
    token = Accounts.generate_admin_session_token(admin)

    conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

    {:ok, _view, html} = live(conn, ~p"/admin/dashboard")
    assert html =~ admin.email
    assert html =~ "Players per region"
    assert html =~ "registration-trend-chart"
    assert html =~ "category-mix-chart"
    assert html =~ "Pipeline by stage"
  end
end
