defmodule CuevolutionWeb.PublicFixturesLiveTest do
  @moduledoc """
  The public fixture list at `/matches` — the whole draw, by category, with
  the same match numbers the tournament director sees.
  """
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp drawn(category \\ "male", count \\ 16) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, category, admin)
    %{bracket: bracket, admin: admin}
  end

  defp opening_fixtures(bracket) do
    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where:
          r.knockout_bracket_id == ^bracket.id and r.code == "W1" and f.bye == false and
            not is_nil(f.participant_a_id) and not is_nil(f.participant_b_id),
        order_by: f.slot
    )
  end

  describe "access" do
    test "no sign-in is needed", %{conn: conn} do
      drawn()

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "Fixtures"
      assert html =~ "SportPesa National Pool Circuit"
    end

    test "it says so before a draw exists", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/matches?category=female")

      assert html =~ "No fixtures yet"
    end

    test "it carries no contact details", %{conn: conn} do
      %{bracket: bracket} = drawn()
      [fixture | _] = opening_fixtures(bracket)
      player = Repo.preload(fixture, participant_a: :player).participant_a.player

      {:ok, _view, html} = live(conn, ~p"/matches")

      refute html =~ player.mobile_number
      refute html =~ "tel:"
    end
  end

  describe "the list" do
    test "every match of the draw is shown, grouped by round", %{conn: conn} do
      drawn()

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "Winners Round 1"
      assert html =~ "Winners Round 3"
      assert html =~ "Losers Round 4"
      assert html =~ "Final"

      # A 16 draw is 29 matches, all of them listed.
      assert html =~ "All 29"
      assert html =~ "29 matches"
    end

    test "matches are numbered across the whole draw", %{conn: conn} do
      drawn()

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ ">M1<"
      assert html =~ ">M29<"
    end

    test "each card links to that match's own page", %{conn: conn} do
      %{bracket: bracket} = drawn()
      [fixture | _] = opening_fixtures(bracket)

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ ~s(href="/m/#{fixture.match_id}")
    end

    test "a double-elimination card says where the loser goes", %{conn: conn} do
      drawn()

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "Loser to M"
    end

    test "the round header counts the whole round", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn()
      [fixture | _] = opening_fixtures(bracket)

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "1 of 8 played"
      assert html =~ "race to 6"
    end
  end

  describe "filters" do
    test "the status pills carry their counts", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn()
      [fixture | _] = opening_fixtures(bracket)

      {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => 2, "b" => 1})

      {:ok, _view, html} = live(conn, ~p"/matches")

      assert html =~ "Live 1"
      assert html =~ "In play"
    end

    test "filtering narrows the list without renumbering the matches", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn()
      [first, second | _] = opening_fixtures(bracket)

      for f <- [first, second] do
        {:ok, _} =
          Competitions.record_result(f, admin, %{
            "winner_participation_id" => f.participant_a_id,
            "score" => %{"a" => 6, "b" => 0}
          })
      end

      {:ok, view, all} = live(conn, ~p"/matches")
      numbers = fn html -> Regex.scan(~r/>(M\d+)</, html) |> Enum.map(&List.last/1) end

      finished = view |> element("button[phx-value-filter='finished']") |> render_click()

      # The finished view is a subset, and every number in it is the number
      # that match had in the full list.
      assert length(numbers.(finished)) < length(numbers.(all))
      assert Enum.all?(numbers.(finished), &(&1 in numbers.(all)))
      assert finished =~ "Decided"
    end

    test "the filter is in the URL so it can be shared", %{conn: conn} do
      drawn()

      {:ok, view, _html} = live(conn, ~p"/matches")

      view |> element("button[phx-value-filter='live']") |> render_click()
      assert_patch(view) =~ "filter=live"
    end

    test "switching category drops the filter rather than carrying it over",
         %{conn: conn} do
      drawn()
      drawn("female", 16)

      {:ok, view, _html} = live(conn, ~p"/matches?filter=finished")

      view |> element("button[phx-value-category='female']") |> render_click()
      path = assert_patch(view)

      assert path =~ "category=female"
      refute path =~ "filter="
    end
  end

  describe "the team event" do
    test "rounds are headed by their group", %{conn: conn} do
      stage = circuit()
      admin = insert(:admin, role: "tournament_director")

      for _ <- 1..20 do
        team = insert(:team)

        insert(:stage_participation,
          stage_id: stage.id,
          category: "team",
          player_id: nil,
          team_id: team.id,
          region_id: team.region_id
        )
      end

      {:ok, _} = Competitions.draw_circuit_team_groups(stage.id, admin)

      {:ok, _view, html} = live(conn, ~p"/matches?category=team")

      assert html =~ "Group A · Round 1"
      assert html =~ "Group B · Round 1"
      assert html =~ "race to 13"
      # Two groups of ten, nine rounds of five matches each.
      assert html =~ "All 90"
    end
  end
end
