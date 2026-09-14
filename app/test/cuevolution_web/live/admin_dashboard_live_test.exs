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

  test "clicking a region chart row opens its directory filter", %{conn: conn} do
    admin = insert(:admin)
    region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
    insert(:player, region_id: region.id, username: "chartregionplayer")
    token = Accounts.generate_admin_session_token(admin)

    conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
    {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

    {:ok, _directory_view, html} =
      view
      |> element("a", region.name)
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ "chartregionplayer"
    assert html =~ ~s(name="filter[region_id]")
  end
end
