defmodule CuevolutionWeb.StandingsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/standings")
  end

  test "shows the no-standings-yet empty state — no Competitions data exists yet", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/standings")

    assert html =~ "Standings"
    assert html =~ "Individual Male"
    assert html =~ "No standings yet"
    assert html =~ "Rankings appear here once the admin records the first match results"
  end

  test "shows the no-standings-yet empty state on every tab", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/standings")

    html =
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='team']")
      |> render_click()

    assert html =~ "No standings yet"
  end

  test "shows the fresh-account banner for a player without a team", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/standings")

    assert html =~ "Welcome to Cuevolution, #{player.first_name}"
  end

  test "does not show the fresh-account banner for a player with a team", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/standings")

    refute html =~ "Welcome to Cuevolution"
  end

  test "applying filters still shows the no-standings-yet state, not the no-filter-matches state",
       %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/standings")

    html =
      view
      |> form("form", %{"region" => "South Rift", "stage" => "Finals"})
      |> render_change()

    assert html =~ "No standings yet"
    refute html =~ "No players match these filters"
  end

  test "shows a ranked participant with real Cuevo Points", %{conn: conn} do
    player = insert(:player)
    fixture = insert(:fixture)
    admin = insert(:admin)

    {:ok, result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    {:ok, _entry} =
      Competitions.record_points(result, admin, %{
        "participant_id" => fixture.participant_a_id,
        "points" => 9
      })

    participant = Cuevolution.Repo.preload(fixture, :participant_a).participant_a
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/standings")

    html =
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='#{participant.category}']")
      |> render_click()

    assert html =~ "9"
    refute html =~ "No standings yet"
  end

  test "a points change from another process live-updates a connected StandingsLive session",
       %{conn: conn} do
    player = insert(:player)
    fixture = insert(:fixture)
    admin = insert(:admin)
    participant = Cuevolution.Repo.preload(fixture, :participant_a).participant_a

    conn = log_in_player(conn, player)
    {:ok, view, _html} = live(conn, ~p"/standings")

    view
    |> element("button[phx-click='switch_tab'][phx-value-tab='#{participant.category}']")
    |> render_click()

    {:ok, result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    {:ok, _entry} =
      Competitions.record_points(result, admin, %{
        "participant_id" => fixture.participant_a_id,
        "points" => 12
      })

    assert render(view) =~ "12"
  end
end
