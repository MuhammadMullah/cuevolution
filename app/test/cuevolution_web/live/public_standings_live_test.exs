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

    test "a burst of frames is coalesced but the last one still lands", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, _html} = live(conn, ~p"/live")

      # A circuit scores frames from two dozen tables at once. Reloads are
      # throttled so a public page cannot be made to recompute per frame per
      # viewer — but whatever the throttle swallows on the way, the score on
      # screen has to end up being the real one.
      for a <- 1..5 do
        {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => a, "b" => 0})
      end

      assert render(view) =~ "1 in play"

      # Past the coalescing window the deferred reload has carried the latest
      # frame through.
      Process.sleep(1_200)
      assert render(view) =~ "5"
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
    test "ranks by SP Points", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      {:ok, view, _html} = live(conn, ~p"/live")
      html = view |> element("button[phx-value-view='table']") |> render_click()

      assert html =~ "SP Points"
      # A win is 3 on top of the 2 for playing; the loser keeps the 2.
      assert html =~ ">5<" or html =~ "5\n"
      assert html =~ "2 for playing"
    end

    test "every statistic from the brief is on the public table", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      {:ok, view, _html} = live(conn, ~p"/live")
      html = view |> element("button[phx-value-view='table']") |> render_click()

      for header <- ~w(MP MW ML MD FW FL FD) do
        assert html =~ header, "#{header} column missing from the public table"
      end

      assert html =~ "SP Points"
      # The 6-2 win: six frames won, two lost, +4 difference.
      assert html =~ "+4"
      assert html =~ "-4"
    end

    test "the table is ordered by SP Points, highest first", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()

      # Play the first round so some players have a win and some do not.
      fixtures =
        Repo.all(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1
        )

      for f <- fixtures do
        Competitions.record_result(f, admin, %{
          "winner_participation_id" => f.participant_a_id,
          "score" => %{"a" => 6, "b" => 1}
        })
      end

      rows = Competitions.standings_for_category("male")
      points = Enum.map(rows, & &1.sp_points)

      assert points == Enum.sort(points, :desc),
             "standings must rank by SP Points, got #{inspect(points)}"

      assert hd(rows).sp_points > List.last(rows).sp_points
    end

    test "the view and category are in the URL so a link can be shared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/live")

      view |> element("button[phx-value-view='table']") |> render_click()
      assert_patch(view) =~ "view=table"

      view |> element("button[phx-value-tab='female']") |> render_click()
      assert assert_patch(view) =~ "category=female"
    end

    test "landing on a shared link opens that view", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/live?category=female&view=table")

      assert html =~ "SP Points"
    end
  end
end
