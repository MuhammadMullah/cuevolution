defmodule CuevolutionWeb.VenueManagementLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/venues")
  end

  test "lists venues, including inactive ones", %{conn: conn} do
    active = insert(:venue, name: "Active Venue")
    inactive = insert(:venue, name: "Inactive Venue", active: false)

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/venues")

    assert html =~ active.name
    assert html =~ inactive.name
  end

  test "creates a new venue", %{conn: conn} do
    region = Repo.get_by!(Region, slug: "nairobi-a")
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    html =
      view
      |> form("#venue-form", venue: %{"name" => "Brand New Venue", "region_id" => region.id})
      |> render_submit()

    assert html =~ "Brand New Venue"
  end

  test "edits an existing venue", %{conn: conn} do
    venue = insert(:venue, name: "Old Name")
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    view |> element("button[phx-click=edit][phx-value-id='#{venue.id}']") |> render_click()

    html =
      view
      |> form("#venue-form", venue: %{"name" => "New Name", "region_id" => venue.region_id})
      |> render_submit()

    assert html =~ "New Name"
    refute html =~ "Old Name"
  end

  test "deactivates a venue", %{conn: conn} do
    venue = insert(:venue, active: true)
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    view
    |> element("button[phx-click=deactivate][phx-value-id='#{venue.id}']")
    |> render_click()

    assert Repo.get!(Cuevolution.Venues.Venue, venue.id).active == false
  end

  test "filters the list by region", %{conn: conn} do
    nairobi_a = Repo.get_by!(Region, slug: "nairobi-a")
    coast = Repo.get_by!(Region, slug: "coast")

    venue_a = insert(:venue, region_id: nairobi_a.id, name: "Nairobi Venue")
    venue_b = insert(:venue, region_id: coast.id, name: "Coast Venue")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    html =
      view
      |> form("#venue-filter-form", filter: %{"region_id" => nairobi_a.id})
      |> render_change()

    assert html =~ venue_a.name
    refute html =~ venue_b.name
  end
end
