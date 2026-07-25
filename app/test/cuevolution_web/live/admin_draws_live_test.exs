defmodule CuevolutionWeb.AdminDrawsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/draws")
  end

  test "shows the fixture-entry shell with no rounds yet, and adding a row works", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/draws")

    assert html =~ "Fixture entry"
    assert html =~ "No rounds scheduled yet"
    assert html =~ "No fixtures entered for this round yet"

    html = view |> element("button", "+ Add row") |> render_click()
    assert Regex.scan(~r/Search name…/, html) |> length() == 4
  end

  test "saving without a round selected shows an error", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    html = view |> element("button", "Save round & notify players") |> render_click()
    assert html =~ "Select or create a round first"
  end

  test "creating a round makes it selectable, and saving a filled row creates a real fixture",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = build(:region)
    player_a = insert(:player, region_id: region.id, gender: "male", first_name: "Jonah")
    player_b = insert(:player, region_id: region.id, gender: "male", first_name: "Amina")

    pa =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player_a.id
      )

    pb =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player_b.id
      )

    venue = insert(:venue, name: "Nakuru Sports Club", region_id: region.id)

    {:ok, group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Pool A"
      })

    Competitions.assign_to_group(pa, group)
    Competitions.assign_to_group(pb, group)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    view |> element("button", "+ New round") |> render_click()

    html =
      view
      |> form("form[phx-submit='create_round']",
        round: %{"name" => "Round 1", "group_id" => group.id}
      )
      |> render_submit()

    assert html =~ "Round 1"
    refute html =~ "No rounds scheduled yet"

    view
    |> element("#draw-row-0-a")
    |> render_keyup(%{"key" => "h", "value" => "Jonah"})

    view
    |> element("button[phx-value-id='#{player_a.id}'][phx-value-field='a']")
    |> render_click()

    view
    |> element("#draw-row-0-b")
    |> render_keyup(%{"key" => "a", "value" => "Amina"})

    view
    |> element("button[phx-value-id='#{player_b.id}'][phx-value-field='b']")
    |> render_click()

    view
    |> element("#draw-row-0-venue")
    |> render_keyup(%{"key" => "k", "value" => "Nakuru"})

    view
    |> element("button[phx-value-id='#{venue.id}'][phx-value-field='venue']")
    |> render_click()

    view
    |> form("#draws-form", %{"rows" => %{"0" => %{"date" => "2026-09-01", "time" => "14:00"}}})
    |> render_change()

    html = view |> element("button", "Save round & notify players") |> render_click()

    assert html =~ "Saved 1 fixture"
    assert html =~ "Jonah"
    assert html =~ "Amina"
    assert html =~ "Nakuru Sports Club"

    fixtures = Repo.all(Fixture)
    assert length(fixtures) == 1
    assert hd(fixtures).participant_a_id == pa.id
    assert hd(fixtures).participant_b_id == pb.id
  end

  test "a row with participants selected but no valid stage registration shows an inline error, and a good row alongside it still saves",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = build(:region)
    player_a = insert(:player, region_id: region.id, gender: "male", first_name: "Jonah")
    player_b = insert(:player, region_id: region.id, gender: "male", first_name: "Amina")

    # Only player_a/player_b get a real StageParticipation (and group
    # membership) — a 3rd player exists but was never registered for this
    # stage, so selecting them will fail resolution inside `enter_fixtures/2`.
    pa =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player_a.id
      )

    pb =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player_b.id
      )

    unregistered = insert(:player, region_id: region.id, gender: "male", first_name: "Ghost")
    venue = insert(:venue, name: "Nakuru Sports Club", region_id: region.id)

    {:ok, group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Pool A"
      })

    Competitions.assign_to_group(pa, group)
    Competitions.assign_to_group(pb, group)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    view |> element("button", "+ New round") |> render_click()

    view
    |> form("form[phx-submit='create_round']",
      round: %{"name" => "Round 1", "group_id" => group.id}
    )
    |> render_submit()

    # Row 0: valid pairing.
    view |> element("#draw-row-0-a") |> render_keyup(%{"key" => "h", "value" => "Jonah"})

    view
    |> element("button[phx-value-id='#{player_a.id}'][phx-value-field='a']")
    |> render_click()

    view |> element("#draw-row-0-b") |> render_keyup(%{"key" => "a", "value" => "Amina"})

    view
    |> element("button[phx-value-id='#{player_b.id}'][phx-value-field='b']")
    |> render_click()

    view |> element("#draw-row-0-venue") |> render_keyup(%{"key" => "k", "value" => "Nakuru"})

    view
    |> element("button[phx-value-id='#{venue.id}'][phx-value-field='venue']")
    |> render_click()

    # Row 1: participant A is unregistered for this stage/group. The
    # suggestion dropdown itself is now scoped to the round's group (spec
    # 007 FR-011), so typing "Ghost" here wouldn't ever surface them as an
    # option — dispatch the underlying `select_field` event directly to
    # simulate a stale/forced selection and exercise the server-side
    # `participant_not_in_group` guard.
    view |> element("button", "+ Add row") |> render_click()

    render_click(view, "select_field", %{
      "row" => "1",
      "field" => "a",
      "id" => unregistered.id,
      "name" => "Ghost",
      "kind" => "player"
    })

    view |> element("#draw-row-1-b") |> render_keyup(%{"key" => "a", "value" => "Amina"})

    view
    |> element("button[phx-value-id='#{player_b.id}'][phx-value-field='b']")
    |> render_click()

    view |> element("#draw-row-1-venue") |> render_keyup(%{"key" => "k", "value" => "Nakuru"})

    view
    |> element("button[phx-value-id='#{venue.id}'][phx-value-field='venue']")
    |> render_click()

    view
    |> form("#draws-form", %{
      "rows" => %{
        "0" => %{"date" => "2026-09-01", "time" => "14:00"},
        "1" => %{"date" => "2026-09-01", "time" => "15:00"}
      }
    })
    |> render_change()

    html = view |> element("button", "Save round & notify players") |> render_click()

    assert html =~ "Saved 1 fixture; 1 row(s) had errors"
    assert html =~ "isn&#39;t a member of this round&#39;s group"

    assert Repo.aggregate(Fixture, :count) == 1
  end

  test "typing a player's name in Participant A shows a matching suggestion, and clicking it fills the field",
       %{conn: conn} do
    player = insert(:player, gender: "male", first_name: "Jonah", last_name: "Otieno")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    html =
      view
      |> element("#draw-row-0-a")
      |> render_keyup(%{"key" => "h", "value" => "Jonah"})

    assert html =~ "Jonah Otieno"
    assert html =~ "@#{player.username}"

    html =
      view
      |> element("button[phx-value-id='#{player.id}'][phx-value-field='a']")
      |> render_click()

    assert html =~ ~s(id="draw-row-0-a")
    assert html =~ "Jonah Otieno"
    refute html =~ "@#{player.username}"
  end

  test "pressing Enter in Participant B accepts the top suggestion", %{conn: conn} do
    insert(:player, gender: "female", first_name: "Amina", last_name: "Wanjiru")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    view
    |> form("#draws-form", %{"rows" => %{"0" => %{"category" => "female"}}})
    |> render_change()

    view
    |> element("#draw-row-0-b")
    |> render_keyup(%{"key" => "a", "value" => "Amina"})

    html =
      view
      |> element("#draw-row-0-b")
      |> render_keyup(%{"key" => "Enter", "value" => "Amina"})

    assert html =~ "Amina Wanjiru"
  end

  test "typing a venue name shows a matching suggestion, and clicking it selects it",
       %{conn: conn} do
    region = build(:region)
    venue = insert(:venue, name: "Nakuru Sports Club", region_id: region.id)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/draws")

    html =
      view
      |> element("#draw-row-0-venue")
      |> render_keyup(%{"key" => "k", "value" => "Nakuru"})

    assert html =~ venue.name

    html =
      view
      |> element("button[phx-value-id='#{venue.id}'][phx-value-field='venue']")
      |> render_click()

    assert html =~ ~s(id="draw-row-0-venue")
    assert html =~ venue.name
  end
end
