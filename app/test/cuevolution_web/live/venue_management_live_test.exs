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

  defp default_region, do: Accounts.list_regions() |> List.first()

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/venues")
  end

  test "lists venues in the default (first) region tab, including inactive ones", %{conn: conn} do
    region = default_region()
    active = insert(:venue, region_id: region.id, name: "Active Venue")
    inactive = insert(:venue, region_id: region.id, name: "Inactive Venue", active: false)

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/venues")

    assert html =~ active.name
    assert html =~ inactive.name
  end

  test "creates a new venue in the selected region", %{conn: conn} do
    region = default_region()
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    html =
      view
      |> form("#venue-form", venue: %{"name" => "Brand New Venue"})
      |> render_submit()

    assert html =~ "Brand New Venue"
    assert Repo.get_by!(Cuevolution.Venues.Venue, name: "Brand New Venue").region_id == region.id
  end

  test "renames an existing venue inline", %{conn: conn} do
    venue = insert(:venue, region_id: default_region().id, name: "Old Name")
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    view |> element("button[phx-click=edit][phx-value-id='#{venue.id}']") |> render_click()

    html =
      view
      |> form("#venue-edit-form", venue: %{"name" => "New Name"})
      |> render_submit()

    assert html =~ "New Name"
    refute html =~ "Old Name"
  end

  test "deactivates and reactivates a venue", %{conn: conn} do
    venue = insert(:venue, region_id: default_region().id, active: true)
    conn = log_in_admin(conn)

    {:ok, view, _html} = live(conn, ~p"/admin/venues")

    view
    |> element("button[phx-click=deactivate][phx-value-id='#{venue.id}']")
    |> render_click()

    assert Repo.get!(Cuevolution.Venues.Venue, venue.id).active == false

    view
    |> element("button[phx-click=activate][phx-value-id='#{venue.id}']")
    |> render_click()

    assert Repo.get!(Cuevolution.Venues.Venue, venue.id).active == true
  end

  test "switching region tabs scopes the venue list", %{conn: conn} do
    nairobi_a = Repo.get_by!(Region, slug: "nairobi-a")
    coast = Repo.get_by!(Region, slug: "coast")

    venue_a = insert(:venue, region_id: nairobi_a.id, name: "Nairobi Venue")
    venue_b = insert(:venue, region_id: coast.id, name: "Coast Venue")

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/venues")

    assert html =~ venue_a.name
    refute html =~ venue_b.name

    html =
      view
      |> element("button[phx-click=select_region][phx-value-id='#{coast.id}']")
      |> render_click()

    assert html =~ venue_b.name
    refute html =~ venue_a.name
  end

  test "shows custom 'Other' venue submissions for the selected region and promotes one", %{
    conn: conn
  } do
    region = default_region()
    player = insert(:player, region_id: region.id, other_venue_name: "Karen Snooker Lounge")

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/venues")

    assert html =~ "Karen Snooker Lounge"
    assert html =~ player.username

    html =
      view
      |> element("button[phx-click=promote][phx-value-name='Karen Snooker Lounge']")
      |> render_click()

    assert html =~ "Karen Snooker Lounge"

    assert Repo.get_by(Cuevolution.Venues.Venue,
             name: "Karen Snooker Lounge",
             region_id: region.id
           )
  end
end
