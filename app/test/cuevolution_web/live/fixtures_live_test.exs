defmodule CuevolutionWeb.FixturesLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Repo

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/fixtures")
  end

  test "shows the no-upcoming-fixtures empty state for a player with no fixtures", %{
    conn: conn
  } do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "My fixtures"
    assert html =~ "No upcoming fixtures"
    refute html =~ "A new draw has been published"
  end

  test "shows the no-results-yet empty state (Competitions.MatchResult doesn't exist yet)", %{
    conn: conn
  } do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "Recent results"
    assert html =~ "No matches played yet"
  end

  test "shows the same empty states for a player with a team", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "No upcoming fixtures"
    assert html =~ "No matches played yet"
  end

  test "shows a real upcoming fixture with opponent, venue, and time", %{conn: conn} do
    grassroots = Repo.get_by!(Competitions.Stage, name: "Grassroots")
    region = build(:region)
    player = insert(:player, region_id: region.id, gender: "male")
    opponent = insert(:player, region_id: region.id, gender: "male", first_name: "Kevin")

    mine =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    theirs =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: opponent.id
      )

    venue = insert(:venue, name: "Nairobi Sports Club", region_id: region.id)
    {:ok, round} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

    row = %{
      "category" => "male",
      "a_kind" => "player",
      "a_id" => player.id,
      "b_kind" => "player",
      "b_id" => opponent.id,
      "venue_id" => venue.id,
      "date" => "2026-09-01",
      "time" => "15:00"
    }

    assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [row])
    assert mine.id != theirs.id

    conn = log_in_player(conn, player)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "A new draw has been published"
    assert html =~ "Kevin"
    assert html =~ "Nairobi Sports Club"
    refute html =~ "No upcoming fixtures"
  end
end
