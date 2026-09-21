defmodule CuevolutionWeb.PlayerDetailLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    player = insert(:player)

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/players/#{player.id}")
  end

  test "shows the player's profile details to a logged-in admin", %{conn: conn} do
    player = insert(:player, first_name: "Detail", last_name: "Test Player")

    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

    {:ok, _view, html} = live(conn, ~p"/admin/players/#{player.id}")

    assert html =~ "Detail Test Player"
    assert html =~ player.username
    assert html =~ player.email
  end

  describe "preferred venue" do
    test "shows 'Not set' when the player has no preferred venue", %{conn: conn} do
      player = insert(:player)
      admin = insert(:admin, role: "super_admin")
      token = Accounts.generate_admin_session_token(admin)
      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

      {:ok, _view, html} = live(conn, ~p"/admin/players/#{player.id}")

      assert html =~ "Not set"
    end

    test "shows the player's current venue name", %{conn: conn} do
      venue = insert(:venue, name: "The Cue Club")
      player = insert(:player, region_id: venue.region_id, preferred_venue_id: venue.id)
      admin = insert(:admin, role: "super_admin")
      token = Accounts.generate_admin_session_token(admin)
      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

      {:ok, _view, html} = live(conn, ~p"/admin/players/#{player.id}")

      assert html =~ "The Cue Club"
    end

    test "an admin with :manage_players can change the venue", %{conn: conn} do
      player = insert(:player)
      venue = insert(:venue, region_id: player.region_id, name: "New Venue")
      admin = insert(:admin, role: "super_admin")
      token = Accounts.generate_admin_session_token(admin)
      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

      {:ok, view, html} = live(conn, ~p"/admin/players/#{player.id}")
      assert html =~ "Edit"

      html = view |> element("button", "Edit") |> render_click()
      assert html =~ "New Venue"

      html = view |> form("form", %{"venue_id" => venue.id}) |> render_submit()

      assert html =~ "Venue updated"
      assert html =~ "New Venue"

      assert Cuevolution.Repo.get!(Cuevolution.Accounts.Player, player.id).preferred_venue_id ==
               venue.id
    end

    test "an admin can change the player's region and venue and notifies them", %{conn: conn} do
      player = insert(:player, notification_preference: "email")
      region = build(:region)
      venue = insert(:venue, region_id: region.id, name: "Regional Venue")
      admin = insert(:admin, role: "super_admin")
      token = Accounts.generate_admin_session_token(admin)
      conn = conn |> init_test_session(%{}) |> put_session(:admin_token, token)

      {:ok, view, _html} = live(conn, ~p"/admin/players/#{player.id}")
      view |> element("button", "Edit") |> render_click()

      view
      |> element("#player-region-select")
      |> render_change(%{"region_id" => region.id})

      view
      |> form("#player-location-form")
      |> render_submit(%{"region_id" => region.id, "venue_id" => venue.id})

      updated = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, player.id)
      assert updated.region_id == region.id
      assert updated.preferred_venue_id == venue.id

      notification =
        Cuevolution.Repo.get_by!(Cuevolution.Notifications.Notification,
          player_id: player.id,
          event_type: "player_location_updated"
        )

      assert notification.channel == "email"
      assert notification.payload["region_name"] == region.name
      assert notification.payload["venue_name"] == venue.name
    end
  end
end
