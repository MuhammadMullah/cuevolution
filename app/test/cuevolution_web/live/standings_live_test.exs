defmodule CuevolutionWeb.StandingsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Group
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  # standings only ever cover Circuit/Finals — `insert(:fixture)` cycles
  # across all 4 stages, so tests asserting a fixture's participant shows
  # up in standings need to pin it to Circuit explicitly.
  defp circuit_fixture(category \\ "male") do
    circuit = Repo.get_by!(Stage, name: "Circuit")
    bracket = Competitions.ensure_knockout_bracket(circuit.id, category)
    participant_a = insert(:stage_participation, stage_id: circuit.id, category: category)
    participant_b = insert(:stage_participation, stage_id: circuit.id, category: category)

    {:ok, round} =
      Competitions.create_round(%{
        stage_id: circuit.id,
        knockout_bracket_id: bracket.id,
        name: "Round of 4"
      })

    insert(:fixture,
      round_id: round.id,
      participant_a_id: participant_a.id,
      participant_b_id: participant_b.id
    )
  end

  # Twenty teams is what the team event takes: two national groups of ten.
  defp drawn_team_groups do
    circuit = Repo.get_by!(Stage, name: "Circuit")
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..20 do
      team = insert(:team)

      insert(:stage_participation,
        stage_id: circuit.id,
        category: "team",
        player_id: nil,
        team_id: team.id,
        region_id: team.region_id
      )
    end

    {:ok, _} = Competitions.draw_circuit_team_groups(circuit.id, admin)
    :ok
  end

  defp open_teams(view) do
    view |> element("button[phx-click='switch_tab'][phx-value-tab='team']") |> render_click()
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

    assert html =~ "Welcome to Sportpesa National Pool Circuit, #{player.first_name}"
  end

  test "does not show the fresh-account banner for a player with a team", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/standings")

    refute html =~ "Welcome to Sportpesa National Pool Circuit"
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
    fixture = circuit_fixture()
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

    participant = Repo.preload(fixture, :participant_a).participant_a
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/standings")

    html =
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='#{participant.category}']")
      |> render_click()

    assert html =~ "9"
    refute html =~ "No standings yet"
  end

  test "shows the match and frame record for a ranked participant", %{conn: conn} do
    player = insert(:player)
    fixture = circuit_fixture()
    admin = insert(:admin)

    {:ok, _result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id,
        "score" => %{"a" => 5, "b" => 3}
      })

    participant = Repo.preload(fixture, :participant_a).participant_a
    conn = log_in_player(conn, player)

    {:ok, view, _html} = live(conn, ~p"/standings")

    html =
      view
      |> element("button[phx-click='switch_tab'][phx-value-tab='#{participant.category}']")
      |> render_click()

    for {label, title} <- CuevolutionWeb.StandingsLive.metric_columns() do
      assert html =~ ~s(title="#{title}"), "the #{label} column is missing"
    end

    # A 5-3 win: both sides played 8 frames, so 5/8 and 3/8 of them.
    assert html =~ "100.0%"
    assert html =~ "62.5%"
    assert html =~ "37.5%"
  end

  test "a points change from another process live-updates a connected StandingsLive session",
       %{conn: conn} do
    player = insert(:player)
    fixture = circuit_fixture()
    admin = insert(:admin)
    participant = Repo.preload(fixture, :participant_a).participant_a

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

  describe "the Teams tab's group standings" do
    setup %{conn: conn} do
      %{conn: log_in_player(conn, insert(:player))}
    end

    test "the scope switch is on the Teams tab only", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/standings")

      refute html =~ "switch_team_scope"
      assert open_teams(view) =~ "switch_team_scope"
    end

    test "the groups scope shows both group tables with the qualification line",
         %{conn: conn} do
      drawn_team_groups()

      {:ok, view, _html} = live(conn, ~p"/standings")
      open_teams(view)

      html =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
        |> render_click()

      assert html =~ "Group A"
      assert html =~ "Group B"
      assert html =~ "Top 4 to the Nationals"

      for {label, title} <- CuevolutionWeb.StandingsLive.metric_columns() do
        assert html =~ ~s(title="#{title}"), "the #{label} column is missing"
      end
    end

    test "a team result shows up in the group table's record", %{conn: conn} do
      drawn_team_groups()
      admin = insert(:admin, role: "tournament_director")

      fixture =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            join: g in Group,
            on: g.id == r.group_id,
            where: g.category == "team" and f.bye == false,
            order_by: [asc: r.sequence, asc: f.slot],
            limit: 1
        )

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 13, "b" => 6}
        })

      {:ok, view, _html} = live(conn, ~p"/standings")
      open_teams(view)

      html =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
        |> render_click()

      # 13 of 19 frames for the winner, 6 for the loser.
      assert html =~ "68.4%"
      assert html =~ "31.6%"
    end

    test "before the draw it says so instead of showing an empty table", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/standings")
      open_teams(view)

      html =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
        |> render_click()

      assert html =~ "No team groups yet"
      assert html =~ "The Circuit team draw has not been made yet"
    end

    test "the overall table survives a round trip through the groups view", %{conn: conn} do
      drawn_team_groups()

      {:ok, view, _html} = live(conn, ~p"/standings")
      overall = open_teams(view)

      # A team name from the flat table, which is streamed.
      [first | _] = Competitions.standings_for_category("team")
      assert overall =~ first.name

      groups =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
        |> render_click()

      assert groups =~ "Group A"

      # Back to Overall: the stream container was removed from the DOM while
      # the groups view was up, so this is the case where a stream comes back
      # empty if it is not reset.
      back =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='overall']")
        |> render_click()

      refute back =~ "Group A"
      assert back =~ first.name
      assert back =~ "SP Points"
    end

    test "the filter is put away in the groups view, where it does nothing", %{conn: conn} do
      drawn_team_groups()

      {:ok, view, _html} = live(conn, ~p"/standings")
      overall = open_teams(view)
      assert overall =~ "standings-filter"

      groups =
        view
        |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
        |> render_click()

      refute groups =~ "standings-filter"
    end

    test "the overall team table claims no qualification of its own", %{conn: conn} do
      drawn_team_groups()

      {:ok, view, _html} = live(conn, ~p"/standings")
      overall = open_teams(view)

      # Team qualification is decided inside a group, so the cumulative table
      # must not paint an advancing accent of its own — it ranks on Cuevo
      # Points, which a team round robin never earns.
      refute overall =~ "border-green-500"
      assert overall =~ "decided inside their group"
    end

    test "leaving the Teams tab resets the scope to overall", %{conn: conn} do
      drawn_team_groups()

      {:ok, view, _html} = live(conn, ~p"/standings")
      open_teams(view)

      view
      |> element("button[phx-click='switch_team_scope'][phx-value-scope='groups']")
      |> render_click()

      view |> element("button[phx-click='switch_tab'][phx-value-tab='male']") |> render_click()
      html = open_teams(view)

      refute html =~ "Group A"
      refute html =~ "Top 4 to the Nationals"
    end
  end
end
