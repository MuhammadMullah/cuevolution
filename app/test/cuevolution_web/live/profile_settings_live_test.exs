defmodule CuevolutionWeb.ProfileSettingsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/profile")
  end

  test "logged-in players can change their notification preference", %{conn: conn} do
    player = insert(:player, notification_preference: "email")
    token = Accounts.generate_player_session_token(player)

    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> element("button[phx-click='set_notification_preference'][phx-value-choice='both']")
      |> render_click()

    assert html =~ "Notification preference saved."
    assert Accounts.get_player_by_session_token(token).notification_preference == "both"
  end

  test "shows the player's personal details", %{conn: conn} do
    region = build(:region)
    venue = insert(:venue, region_id: region.id, name: "Cue Club Alpha")

    player =
      insert(:player,
        first_name: "Jane",
        last_name: "Doe",
        username: "janedoe",
        gender: "female",
        date_of_birth: ~D[1994-03-12],
        region_id: region.id,
        preferred_venue_id: venue.id,
        email: "jane@example.com",
        mobile_number: "+254712345678",
        location: "Nairobi"
      )

    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, _view, html} = live(conn, ~p"/profile")

    assert html =~ "@janedoe"
    assert html =~ "Female"
    assert html =~ "12 Mar 1994"
    assert html =~ Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(region.name))
    assert html =~ "Cue Club Alpha"
    assert html =~ "jane@example.com"
    assert html =~ "+254712345678"
    assert html =~ "Nairobi"
    assert html =~ "No team yet"
  end
end
