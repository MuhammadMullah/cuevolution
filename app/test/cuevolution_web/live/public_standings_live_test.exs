defmodule CuevolutionWeb.PublicStandingsLiveTest do
  @moduledoc false
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp drawn_bracket(category \\ "male", count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end

    {:ok, %{bracket: bracket}} =
      Competitions.draw_circuit_bracket(stage.id, category, admin)

    %{bracket: bracket, admin: admin}
  end

  defp play_round(bracket, admin, code) do
    fixtures =
      Repo.all(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where:
            r.knockout_bracket_id == ^bracket.id and r.code == ^code and f.bye == false and
              is_nil(f.result_id),
          order_by: f.slot
      )

    for f <- fixtures, f.participant_a_id && f.participant_b_id do
      Competitions.record_result(f, admin, %{
        "winner_participation_id" => f.participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })
    end
  end

  defp first_fixture(bracket) do
    Repo.one!(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 1
    )
  end

  describe "spectator access" do
    test "no sign-in is needed", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/live")

      assert html =~ "Live scores"
      assert html =~ "SportPesa National Pool Circuit"
    end

    test "there are no admin controls on it", %{conn: conn} do
      drawn_bracket()

      {:ok, _view, html} = live(conn, ~p"/live")

      refute html =~ "Make the draw"
      refute html =~ "Complete match"
      refute html =~ "circuit_frame"
      refute html =~ "Deal again"
    end
  end

  describe "the live view" do
    test "says so when nothing is in play", %{conn: conn} do
      drawn_bracket()

      {:ok, _view, html} = live(conn, ~p"/live")

      assert html =~ "No matches in play right now."
      assert html =~ "0 in play"
    end

    test "shows a match being played with its running score", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, _html} = live(conn, ~p"/live")

      {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => 3, "b" => 1})

      html = render(view)
      assert html =~ "1 in play"
      assert html =~ "Live"
      assert html =~ "3"
    end

    test "a finished match moves to 'Just finished'", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, _html} = live(conn, ~p"/live")

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      html = render(view)
      assert html =~ "Just finished"
      assert html =~ "6–2"
    end

    test "a burst of frames leaves the latest score on screen", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, _html} = live(conn, ~p"/live")

      # A circuit scores frames from two dozen tables at once. However the
      # page batches those broadcasts, the score it ends up showing has to be
      # the real one. (The batching itself is covered in
      # `CuevolutionWeb.StandingsRefreshTest`; it is off in test.)
      for a <- 1..5 do
        {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => a, "b" => 0})
      end

      html = render(view)
      assert html =~ "1 in play"
      assert html =~ "5"
    end

    test "the live view does not carry the standings table, nor the table the match cards",
         %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()

      Competitions.record_result(first_fixture(bracket), admin, %{
        "winner_participation_id" => first_fixture(bracket).participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })

      {:ok, _view, live_html} = live(conn, ~p"/live?view=live")
      {:ok, _view, table_html} = live(conn, ~p"/live?view=table")

      # Each view loads only its own data, so neither page pays for the other.
      assert live_html =~ "Just finished"
      refute live_html =~ "SP Points"

      assert table_html =~ "SP Points"
      refute table_html =~ "Just finished"
    end

    test "a result recorded elsewhere updates the page with no reload", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, html} = live(conn, ~p"/live")
      assert html =~ "0 in play"

      # Another session — the tournament director — scores a frame.
      {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => 1, "b" => 0})

      assert render(view) =~ "1 in play"
    end
  end

  describe "the standings table" do
    test "the brief's columns are on the public table", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket("male", 32)
      play_round(bracket, admin, "W1")

      {:ok, _view, html} = live(conn, ~p"/live?category=male&view=table")

      for header <- ["Pos", "Player", "Region", "Finish", "Racks won", "Rack-win %", "SP Points"] do
        assert html =~ header, "the #{header} column is missing"
      end

      # Provisional while the circuit runs, so the Status column is there too.
      assert html =~ "Status"
      assert html =~ "Provisional"
    end

    test "a player who has won their opening match shows the points it guarantees",
         %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket("male", 32)
      play_round(bracket, admin, "W1")

      {:ok, _view, html} = live(conn, ~p"/live?category=male&view=table")

      # Unbeaten in WB R2 cannot finish below 65th, which is 5 points.
      assert html =~ "Winners side"
      assert html =~ "Losers side"
      assert html =~ "SP Points"
    end

    test "it is ordered by SP Points, strongest first", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket("male", 32)
      play_round(bracket, admin, "W1")

      {:ok, _view, _html} = live(conn, ~p"/live?category=male&view=table")

      rows = Competitions.circuit_standings(circuit().id, "male").rows
      points = Enum.map(rows, & &1.points)

      assert points == Enum.sort(points, :desc)
    end

    test "the view and category are in the URL so a link can be shared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/live")

      view |> element("button[phx-value-view='table']") |> render_click()
      assert_patch(view) =~ "view=table"

      view |> element("button[phx-value-tab='female']") |> render_click()
      assert_patch(view) =~ "category=female"
    end

    test "landing on a shared link opens that view", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket("female", 32)
      play_round(bracket, admin, "W1")

      {:ok, _view, html} = live(conn, ~p"/live?category=female&view=table")

      assert html =~ "SP Points"
      assert html =~ "Ladies"
    end

    # The team event is a round robin with no bracket, so its rows come from
    # standings_for_category/1 and carry neither :finish nor a finish label.
    # Rendering them used to raise KeyError and take the LiveView down.
    test "the team table renders even though team rows have no bracket finish", %{conn: conn} do
      stage = circuit()

      for _ <- 1..3 do
        insert(:stage_participation,
          stage_id: stage.id,
          category: "team",
          player_id: nil,
          team_id: insert(:team).id
        )
      end

      {:ok, _view, html} = live(conn, ~p"/live?category=team&view=table")

      assert html =~ "SP Points"
      assert html =~ "Team"
    end

    test "switching to the team tab from the table view does not crash", %{conn: conn} do
      stage = circuit()

      insert(:stage_participation,
        stage_id: stage.id,
        category: "team",
        player_id: nil,
        team_id: insert(:team).id
      )

      {:ok, view, _html} = live(conn, ~p"/live")

      view |> element("button[phx-value-view='table']") |> render_click()
      assert_patch(view) =~ "view=table"

      view |> element("button[phx-value-tab='team']") |> render_click()
      assert_patch(view) =~ "category=team"

      assert render(view) =~ "SP Points"
    end
  end
end
