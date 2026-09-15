defmodule CuevolutionWeb.VenuePlayersLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp nairobi_a, do: Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    venue = insert(:venue)

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/venues/#{venue.id}/players")
  end

  test "lists players registered at the venue, with tiles and the region link", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id, name: "Eldoret Highland Cue")
    other_venue = insert(:venue, region_id: region.id)

    insert(:player,
      region_id: region.id,
      preferred_venue_id: venue.id,
      gender: "male",
      username: "venueplayerone"
    )

    insert(:player,
      region_id: region.id,
      preferred_venue_id: other_venue.id,
      username: "elsewhere"
    )

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    assert html =~ "Eldoret Highland Cue"
    assert html =~ "venueplayerone"
    refute html =~ "elsewhere"
    assert html =~ "Manage #{region.name} venues"
    assert html =~ "Showing 1 of 1 players"
  end

  test "search narrows the roster", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id)

    insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "findmeplease")
    insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "someoneelse")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    html =
      view
      |> form("#venue-players-filter-form", venue_players_filter: %{"q" => "findmeplease"})
      |> render_change()

    assert html =~ "findmeplease"
    refute html =~ "someoneelse"
  end

  test "kind chips filter between individuals and team players", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id)
    team = insert(:team)

    insert(:player,
      region_id: region.id,
      preferred_venue_id: venue.id,
      gender: "male",
      username: "individualmale"
    )

    insert(:player,
      region_id: region.id,
      preferred_venue_id: venue.id,
      team_id: team.id,
      username: "teammember"
    )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    html = view |> element("button", "Teams") |> render_click()

    assert html =~ "teammember"
    assert html =~ team.name
    refute html =~ "individualmale"

    html = view |> element("button", "Male") |> render_click()

    assert html =~ "individualmale"
    refute html =~ "teammember"
  end

  test "shows an empty state when no player matches the filters", %{conn: conn} do
    venue = insert(:venue)
    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    assert html =~ "No players at this venue match those filters."
  end

  test "clicking a row opens a detail modal without navigating away", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id)

    player =
      insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "rowclicker")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    html = view |> element("div[phx-click='open_player']", "rowclicker") |> render_click()

    assert html =~ "@#{player.username}"
    assert html =~ "Notification delivery history"
    assert html =~ "Anonymize this record"
  end

  test "closes the detail modal", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id)
    insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "rowclicker")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    view |> element("div[phx-click='open_player']", "rowclicker") |> render_click()
    html = view |> element("button", "✕") |> render_click()

    refute html =~ "Notification delivery history"
  end

  test "anonymizing from the modal removes the player from the roster", %{conn: conn} do
    region = nairobi_a()
    venue = insert(:venue, region_id: region.id)

    insert(:player, region_id: region.id, preferred_venue_id: venue.id, username: "toanonymize")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/venues/#{venue.id}/players")

    view |> element("div[phx-click='open_player']", "toanonymize") |> render_click()
    view |> element("button", "Anonymize this record") |> render_click()
    html = view |> element("button", "Yes, anonymize") |> render_click()

    refute html =~ "toanonymize"
    assert html =~ "Player anonymized."
    assert html =~ "Showing 0 of 0 players"
  end
end
