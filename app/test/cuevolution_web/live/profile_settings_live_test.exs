defmodule CuevolutionWeb.ProfileSettingsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/profile")
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

  test "can navigate to the Settings tab", %{conn: conn} do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> element("a", "Settings")
      |> render_click()

    assert html =~ "Password"
    assert html =~ "Notifications"
  end

  test "logged-in players can change their notification preference from Settings", %{conn: conn} do
    player = insert(:player, notification_preference: "email")
    token = Accounts.generate_player_session_token(player)

    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile/settings")

    html =
      view
      |> element("button[phx-click='set_notification_preference'][phx-value-choice='both']")
      |> render_click()

    assert html =~ "Notification preference saved."
    assert Accounts.get_player_by_session_token(token).notification_preference == "both"
  end

  test "players can update their password from Settings", %{conn: conn} do
    player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("OldPass1!"))
    token = Accounts.generate_player_session_token(player)

    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile/settings")

    html =
      view
      |> form("#profile-password-form",
        player: %{
          current_password: "OldPass1!",
          password: "NewPass1!",
          password_confirmation: "NewPass1!"
        }
      )
      |> render_submit()

    assert html =~ "Password updated."

    assert {:ok, _} =
             Accounts.authenticate_player(player.username, "NewPass1!")
  end

  test "rejects a password change with the wrong current password", %{conn: conn} do
    player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("OldPass1!"))
    token = Accounts.generate_player_session_token(player)

    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile/settings")

    html =
      view
      |> form("#profile-password-form",
        player: %{
          current_password: "WrongPass1!",
          password: "NewPass1!",
          password_confirmation: "NewPass1!"
        }
      )
      |> render_submit()

    assert html =~ "is incorrect"

    assert {:error, :invalid_credentials} =
             Accounts.authenticate_player(player.username, "NewPass1!")
  end

  test "players can change their venue without touching their region", %{conn: conn} do
    region = build(:region)
    old_venue = insert(:venue, region_id: region.id, name: "Old Venue")
    new_venue = insert(:venue, region_id: region.id, name: "New Venue")

    player = insert(:player, region_id: region.id, preferred_venue_id: old_venue.id)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> element("form[phx-submit='save_location']")
      |> render_submit(%{"region_id" => region.id, "venue_id" => new_venue.id})

    assert html =~ "Location updated."
    updated = Accounts.get_player_by_session_token(token)
    assert updated.preferred_venue_id == new_venue.id
    assert updated.region_id == region.id
  end

  test "changing region requires picking a venue from the new region", %{conn: conn} do
    old_region = build(:region)
    old_venue = insert(:venue, region_id: old_region.id)
    player = insert(:player, region_id: old_region.id, preferred_venue_id: old_venue.id)

    new_region = Accounts.list_regions() |> Enum.find(&(&1.id != old_region.id))
    new_venue = insert(:venue, region_id: new_region.id, name: "Brand New Venue")

    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> element("form[phx-submit='save_location']")
      |> render_submit(%{"region_id" => new_region.id, "venue_id" => new_venue.id})

    assert html =~ "Location updated."
    updated = Accounts.get_player_by_session_token(token)
    assert updated.region_id == new_region.id
    assert updated.preferred_venue_id == new_venue.id
  end

  test "players can edit their username, date of birth, and town", %{conn: conn} do
    player = insert(:player, username: "oldname", location: "Mombasa")
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, html} = live(conn, ~p"/profile")
    refute html =~ ~s(name="player[username]")

    html =
      view
      |> element("button[phx-click='toggle_personal_edit']")
      |> render_click()

    assert html =~ ~s(name="player[username]")

    html =
      view
      |> form("#personal-details-form",
        player: %{
          username: "newname",
          date_of_birth: "1990-05-15",
          location: "Kisumu"
        }
      )
      |> render_submit()

    assert html =~ "Profile updated."
    updated = Accounts.get_player_by_session_token(token)
    assert updated.username == "newname"
    assert updated.date_of_birth == ~D[1990-05-15]
    assert updated.location == "Kisumu"
  end

  test "rejects a username already taken while editing personal details", %{conn: conn} do
    insert(:player, username: "takenname")
    player = insert(:player, username: "myname")
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    view
    |> element("button[phx-click='toggle_personal_edit']")
    |> render_click()

    html =
      view
      |> form("#personal-details-form",
        player: %{
          username: "takenname",
          date_of_birth: "1990-05-15",
          location: "Kisumu"
        }
      )
      |> render_submit()

    assert html =~ "has already been taken"
    assert Accounts.get_player_by_session_token(token).username == "myname"
  end

  test "opening the deactivate modal shows the confirmation prompt", %{conn: conn} do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    html =
      view
      |> element("button[phx-click='open_deactivate_modal']")
      |> render_click()

    assert html =~ "Deactivate your account"
    assert html =~ "DEACTIVATE"
  end

  test "the deactivate button stays disabled until the exact phrase is typed", %{conn: conn} do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    view
    |> element("button[phx-click='open_deactivate_modal']")
    |> render_click()

    view
    |> element("form[phx-submit='deactivate_account']")
    |> render_change(%{"confirmation" => "deactivate"})

    assert has_element?(
             view,
             "form[phx-submit='deactivate_account'] button[type='submit'][disabled]"
           )

    view
    |> element("form[phx-submit='deactivate_account']")
    |> render_change(%{"confirmation" => "DEACTIVATE"})

    refute has_element?(
             view,
             "form[phx-submit='deactivate_account'] button[type='submit'][disabled]"
           )
  end

  test "typing DEACTIVATE and submitting anonymizes the account and signs the player out", %{
    conn: conn
  } do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    view
    |> element("button[phx-click='open_deactivate_modal']")
    |> render_click()

    assert {:error, {:redirect, %{to: "/login"}}} =
             view
             |> element("form[phx-submit='deactivate_account']")
             |> render_submit(%{"confirmation" => "DEACTIVATE"})

    refute Accounts.get_player_by_session_token(token)
    reloaded = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, player.id)
    assert reloaded.anonymized_at
  end

  test "submitting the deactivate form with the wrong phrase does nothing", %{conn: conn} do
    player = insert(:player)
    token = Accounts.generate_player_session_token(player)
    conn = conn |> init_test_session(%{}) |> put_session(:player_token, token)

    {:ok, view, _html} = live(conn, ~p"/profile")

    view
    |> element("button[phx-click='open_deactivate_modal']")
    |> render_click()

    view
    |> element("form[phx-submit='deactivate_account']")
    |> render_submit(%{"confirmation" => "not it"})

    assert Accounts.get_player_by_session_token(token)
    refute Cuevolution.Repo.get!(Cuevolution.Accounts.Player, player.id).anonymized_at
  end
end
