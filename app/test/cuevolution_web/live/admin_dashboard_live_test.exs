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
    assert html =~ "Category mix"
    assert html =~ "Individual male"
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

  describe "Players per venue" do
    test "lists active venues with their player counts", %{conn: conn} do
      admin = insert(:admin)
      region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      venue = insert(:venue, region_id: region.id, name: "Eldoret Highland Cue")
      insert(:player, region_id: region.id, preferred_venue_id: venue.id, gender: "male")
      token = Accounts.generate_admin_session_token(admin)

      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Players per venue"
      assert html =~ "Eldoret Highland Cue"
    end

    test "search narrows the venue list", %{conn: conn} do
      admin = insert(:admin)
      region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      insert(:venue, region_id: region.id, name: "Kilimani Rack House")
      insert(:venue, region_id: region.id, name: "Westlands Cue Club")
      token = Accounts.generate_admin_session_token(admin)

      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html =
        view
        |> form("#venue-filter-form", venue_filter: %{"q" => "Kilimani"})
        |> render_change()

      assert html =~ "Kilimani Rack House"
      refute html =~ "Westlands Cue Club"
    end

    test "region filter narrows the venue list", %{conn: conn} do
      admin = insert(:admin)
      nairobi_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      coast = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")
      insert(:venue, region_id: nairobi_a.id, name: "Nairobi Only Venue")
      insert(:venue, region_id: coast.id, name: "Coast Only Venue")
      token = Accounts.generate_admin_session_token(admin)

      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html =
        view
        |> form("#venue-filter-form", venue_filter: %{"region_id" => coast.id})
        |> render_change()

      assert html =~ "Coast Only Venue"
      refute html =~ "Nairobi Only Venue"
    end

    test "shows an empty state when no venue matches the search", %{conn: conn} do
      admin = insert(:admin)
      token = Accounts.generate_admin_session_token(admin)

      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      html =
        view
        |> form("#venue-filter-form", venue_filter: %{"q" => "zzzznotarealvenue"})
        |> render_change()

      assert html =~ "No venues match that search."
    end

    test "clicking a venue row opens that venue's player directory page", %{conn: conn} do
      admin = insert(:admin)
      region = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
      venue = insert(:venue, region_id: region.id, name: "Eldoret Highland Cue")
      insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "venueplayer")
      token = Accounts.generate_admin_session_token(admin)

      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      {:ok, venue_players_view, html} =
        view
        |> element("a", venue.name)
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/venues/#{venue.id}/players")

      assert html =~ "venueplayer"
      assert render(venue_players_view) =~ "Manage #{region.name} venues"
    end
  end
end
