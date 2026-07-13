defmodule CuevolutionWeb.RegistrationLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo

  defp fill(view, attrs) do
    view
    |> form("#registration-form", player: attrs)
    |> render_change()
  end

  defp continue(view) do
    view |> element("button", "Continue") |> render_click()
  end

  defp choose(view, field, value) do
    view
    |> element(
      "button[phx-click='choose'][phx-value-field='#{field}'][phx-value-choice='#{value}']"
    )
    |> render_click()
  end

  defp choose_region(view, region_id) do
    view
    |> element("button[phx-click='choose_region'][phx-value-id='#{region_id}']")
    |> render_click()
  end

  defp step_1_attrs do
    %{
      "first_name" => "Jane",
      "last_name" => "Doe",
      "date_of_birth" => Date.add(Date.utc_today(), -365 * 20) |> Date.to_iso8601(),
      "location" => "Nairobi"
    }
  end

  defp step_2_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "jane#{System.unique_integer([:positive])}@example.com",
        "mobile_number" => "0712345678",
        "username" => "janedoe#{System.unique_integer([:positive])}",
        "password" => "Valid1!Pass"
      },
      overrides
    )
  end

  defp complete_steps_1_and_2(view) do
    fill(view, step_1_attrs())
    choose(view, "gender", "female")
    continue(view)

    fill(view, step_2_attrs())
    continue(view)
  end

  test "renders step 1 with a progress indicator", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/register")
    assert html =~ "Your details"
    assert html =~ "Step 1 of 4"
  end

  test "blocks advancing past step 1 with an age under 18", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    fill(
      view,
      Map.put(
        step_1_attrs(),
        "date_of_birth",
        Date.add(Date.utc_today(), -365 * 10) |> Date.to_iso8601()
      )
    )

    choose(view, "gender", "female")
    html = continue(view)

    assert html =~ "must be at least 18 years old"
    assert html =~ "Step 1 of 4"
  end

  test "does not show a premature error for an untouched category pill", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    # Fills every other step-1 field but leaves the Category pills untouched —
    # any "can't be blank" left over must be a premature error for gender.
    html = fill(view, step_1_attrs())
    refute html =~ "can&#39;t be blank"
  end

  test "shows the error once Continue is clicked without choosing a category", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    fill(view, step_1_attrs())
    html = continue(view)

    assert html =~ "can&#39;t be blank"
    assert html =~ "Step 1 of 4"
  end

  test "does not show a stray error after choosing a category", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    fill(view, step_1_attrs())
    html = choose(view, "gender", "male")

    refute html =~ "can&#39;t be blank"
  end

  test "shows every blocked field's error when Continue is clicked on a blank step", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/register")

    html = continue(view)

    assert html =~ "Step 1 of 4"
    assert Regex.scan(~r/can&#39;t be blank/, html) |> length() >= 4
  end

  test "advances through steps and back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    fill(view, step_1_attrs())
    choose(view, "gender", "male")
    html = continue(view)
    assert html =~ "Step 2 of 4"
    assert html =~ "Contact"

    html = view |> element("button", "Back") |> render_click()
    assert html =~ "Step 1 of 4"
  end

  test "shows a live username-availability hint", %{conn: conn} do
    insert(:player, username: "takenname")
    {:ok, view, _view_html} = live(conn, ~p"/register")

    complete_steps_1_and_2(view)
    # complete_steps_1_and_2 already used a unique username; go back to check the hint directly
    view |> element("button", "Back") |> render_click()

    html = fill(view, %{"username" => "brandnewname"})
    assert html =~ "brandnewname is available"
    assert html =~ "text-green-600"

    html = fill(view, %{"username" => "takenname"})
    refute html =~ "is available"
    assert html =~ "takenname is already taken"
    assert html =~ "text-danger"
  end

  test "shows a live email-availability hint", %{conn: conn} do
    insert(:player, email: "taken@example.com")
    {:ok, view, _view_html} = live(conn, ~p"/register")

    complete_steps_1_and_2(view)
    view |> element("button", "Back") |> render_click()

    html = fill(view, %{"email" => "brand-new@example.com"})
    assert html =~ "✓ available"
    assert html =~ "text-green-600"

    html = fill(view, %{"email" => "taken@example.com"})
    refute html =~ "✓ available"
    assert html =~ "An account with this email already exists"
    assert html =~ "text-danger"
  end

  test "shows a live mobile-number-taken hint", %{conn: conn} do
    insert(:player, mobile_number: "+254712345678")
    {:ok, view, _view_html} = live(conn, ~p"/register")

    complete_steps_1_and_2(view)
    view |> element("button", "Back") |> render_click()

    html = fill(view, %{"mobile_number" => "0798765432"})
    assert html =~ "Will be saved as +254798765432"

    html = fill(view, %{"mobile_number" => "0712345678"})
    refute html =~ "Will be saved as"
    assert html =~ "This number is already registered"
    assert html =~ "text-danger"
  end

  test "step 3 loads venues for the chosen region and supports Other", %{conn: conn} do
    region = build(:region)
    insert(:venue, region_id: region.id, name: "Cue Club Alpha")

    {:ok, view, _html} = live(conn, ~p"/register")
    complete_steps_1_and_2(view)

    html = choose_region(view, region.id)
    assert html =~ "Cue Club Alpha"

    assert html =~
             "Preferred venue in #{Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(region.name))}"

    refute html =~ "Type the venue name"

    html = choose(view, "venue_choice", "other")
    assert html =~ "Type the venue name"
  end

  test "completing all steps creates the account and logs the player in", %{conn: conn} do
    region = build(:region)
    venue = insert(:venue, region_id: region.id)

    {:ok, view, _html} = live(conn, ~p"/register")
    complete_steps_1_and_2(view)

    choose_region(view, region.id)
    choose(view, "preferred_venue_id", venue.id)
    continue(view)

    html = choose(view, "notification_preference", "email")
    assert html =~ "Both"

    html =
      view
      |> form("#registration-form")
      |> render_submit()

    assert html =~ "You&#39;re registered!"
    assert html =~ "Enter the app"

    player = Repo.get_by(Player, first_name: "Jane", last_name: "Doe")
    assert player
    assert player.preferred_venue_id == venue.id
    assert player.region_id == region.id
  end

  test "uploads and stores a resized profile picture", %{conn: conn} do
    region = build(:region)

    {:ok, view, _html} = live(conn, ~p"/register")

    fixture_path = Path.join([__DIR__, "..", "..", "support", "fixtures", "avatar.jpg"])

    photo =
      file_input(view, "#registration-form", :photo, [
        %{
          last_modified: 1_594_171_879_000,
          name: "avatar.jpg",
          content: File.read!(fixture_path),
          size: File.stat!(fixture_path).size,
          type: "image/jpeg"
        }
      ])

    assert render_upload(photo, "avatar.jpg") =~ "phx-preview"

    fill(view, step_1_attrs())
    choose(view, "gender", "female")
    continue(view)
    fill(view, step_2_attrs())
    continue(view)
    choose_region(view, region.id)
    choose(view, "venue_choice", "other")
    fill(view, %{"other_venue_name" => "Some Hall"})
    continue(view)
    choose(view, "notification_preference", "email")

    view |> form("#registration-form") |> render_submit()

    player = Repo.get_by(Player, first_name: "Jane", last_name: "Doe")
    assert player.profile_picture_path
    assert String.starts_with?(player.profile_picture_path, "players/")

    stored_path =
      Path.join([:code.priv_dir(:cuevolution), "static", "uploads", player.profile_picture_path])

    assert File.exists?(stored_path)
  end
end
