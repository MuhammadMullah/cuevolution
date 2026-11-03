defmodule CuevolutionWeb.CircuitTeamsLiveTest do
  @moduledoc """
  The Circuit team event on the Groups screen: a round robin in two national
  groups, drawn and scored on the same page as the singles brackets.
  """
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp as_td(conn), do: log_in_admin(conn, insert(:admin, role: "tournament_director"))

  defp enter_teams(count) do
    stage = circuit()

    for _ <- 1..count do
      team = insert(:team)

      insert(:stage_participation,
        stage_id: stage.id,
        category: "team",
        player_id: nil,
        team_id: team.id,
        region_id: team.region_id
      )
    end
  end

  # Returns the rendered Teams tab.
  defp open_teams(view) do
    view |> element("button[phx-value-id='#{circuit().id}']") |> render_click()
    view |> element("button[phx-value-category='team']") |> render_click()
  end

  defp round_one_fixtures do
    group_ids =
      Competitions.circuit_team_groups(circuit().id) |> Enum.map(& &1.id)

    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.group_id in ^group_ids and r.sequence == 1,
        order_by: f.match_id
    )
  end

  describe "before the draw" do
    test "the entered teams are listed with a count", %{conn: conn} do
      enter_teams(20)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = open_teams(view)

      assert html =~ "No Teams draw yet"
      assert html =~ "20"
      assert html =~ "Entered — Teams Circuit (20)"
      assert html =~ "Make the draw"
    end

    test "there is no bracket chart on the Teams tab", %{conn: conn} do
      enter_teams(20)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = open_teams(view)

      refute html =~ "Full chart"
      refute html =~ "Winners Round 1"
    end

    test "fewer than ten teams cannot be drawn", %{conn: conn} do
      enter_teams(9)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = open_teams(view)

      assert html =~ "At least 10 teams are needed"
      refute html =~ "Make the draw"
    end

    test "a read-only admin is told they cannot draw", %{conn: conn} do
      enter_teams(20)
      conn = log_in_admin(conn, insert(:admin, role: "regional_coordinator"))

      {:ok, view, _html} = live(conn, ~p"/admin/groups")
      html = open_teams(view)

      assert html =~ "Only a tournament director can make the draw."
      refute html =~ "Make the draw"
    end
  end

  describe "making the draw" do
    setup %{conn: conn} do
      enter_teams(20)
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      open_teams(view)
      view |> element("button[phx-click='draw_circuit_teams']") |> render_click()
      %{view: view}
    end

    test "both groups appear with their tables", %{view: view} do
      html = render(view)

      assert html =~ "Group A"
      assert html =~ "Group B"
      assert html =~ "SP Points"
      assert html =~ "Top 4 to the Nationals"
    end

    test "every team starts on the 2 points for entering", %{view: view} do
      html = render(view)

      # Twenty teams, all on 2 — the entering points, before a ball is struck.
      assert Competitions.circuit_team_standings(circuit().id)
             |> Enum.flat_map(& &1.rows)
             |> Enum.all?(&(&1.sp_points == 2))

      assert html =~ "Group tables"
    end

    test "the fixtures view lists round one", %{view: view} do
      html = view |> element("button[phx-value-view='fixtures']") |> render_click()

      assert html =~ "Round 1"
      assert html =~ "race to 14"
      assert html =~ "To play"
    end

    test "the draw can be dealt again before any result", %{view: view} do
      html = render(view)
      assert html =~ "Deal again"

      before = Competitions.circuit_team_groups(circuit().id) |> Enum.map(& &1.id)

      view |> element("button[phx-click='redraw_circuit_teams']") |> render_click()

      after_redraw = Competitions.circuit_team_groups(circuit().id) |> Enum.map(& &1.id)

      assert length(after_redraw) == 2
      refute Enum.any?(after_redraw, &(&1 in before)), "the old groups should be replaced"
    end

    test "the draw can be cleared back to the entrant list", %{view: view} do
      html = view |> element("button[phx-click='reset_circuit_teams']") |> render_click()

      assert html =~ "No Teams draw yet"
      assert Competitions.circuit_team_draw(circuit().id) == nil
    end
  end

  describe "scoring a team match" do
    setup %{conn: conn} do
      enter_teams(20)
      admin = insert(:admin, role: "tournament_director")
      {:ok, _} = Competitions.draw_circuit_team_groups(circuit().id, admin)

      {:ok, view, _html} = live(log_in_admin(conn, admin), ~p"/admin/groups")
      open_teams(view)
      view |> element("button[phx-value-view='fixtures']") |> render_click()

      %{view: view, admin: admin}
    end

    test "selecting a fixture opens the score panel", %{view: view} do
      [fixture | _] = round_one_fixtures()

      html = view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()

      assert html =~ "race to 14"
    end

    test "a result recorded elsewhere moves the group table", %{view: view, admin: admin} do
      [fixture | _] = round_one_fixtures()

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 14, "b" => 6}
        })

      [row | _] =
        Competitions.circuit_team_standings(circuit().id)
        |> Enum.flat_map(& &1.rows)
        |> Enum.filter(&(&1.participation.id == fixture.participant_a_id))

      # 2 for entering + 3 for the win, and the frames carried through.
      assert row.sp_points == 5
      assert row.frames_won == 14
      assert row.frames_lost == 6

      html = view |> element("button[phx-value-view='table']") |> render_click()
      assert html =~ "SP Points"
    end

    test "the draw can no longer be re-dealt once a result exists", %{view: view, admin: admin} do
      [fixture | _] = round_one_fixtures()

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 14, "b" => 0}
        })

      html = view |> element("button[phx-value-view='table']") |> render_click()

      refute html =~ "Deal again"
      refute html =~ "Clear draw"
    end
  end
end
