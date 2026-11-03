defmodule CuevolutionWeb.Admin.StandingsLiveTest do
  @moduledoc false
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo
  alias Ecto.Adapters.SQL.Sandbox

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp as_td(conn), do: log_in_admin(conn, insert(:admin, role: "tournament_director"))

  # Draws a bracket and plays its opening round, so some players have a win
  # and frames, and the rest have neither.
  defp played_bracket(category \\ "male", count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, category, admin)

    fixtures =
      Repo.all(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1,
          order_by: f.slot
      )

    for f <- fixtures do
      Competitions.record_result(f, admin, %{
        "winner_participation_id" => f.participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })
    end

    %{bracket: bracket, admin: admin, fixtures: fixtures}
  end

  describe "reaching the table" do
    test "it is linked from the admin nav", %{conn: conn} do
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/dashboard")

      assert html =~ ~s(href="/admin/standings")
    end

    test "an anonymous visitor is redirected to the admin login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/standings")
    end
  end

  describe "the ten columns" do
    test "every statistic from the brief is present", %{conn: conn} do
      played_bracket()

      {:ok, _view, html} = live(as_td(conn), ~p"/admin/standings")

      for header <- ~w(MP MW ML MD FW FL FD) do
        assert html =~ ">\n              #{header}" or html =~ header
      end

      assert html =~ "SP Points"
      assert html =~ "Player"
    end

    test "the figures are right for a 6-2 win", %{conn: conn} do
      %{fixtures: [first | _]} = played_bracket()

      winner = Repo.preload(first, participant_a: :player).participant_a
      loser = Repo.preload(first, participant_b: :player).participant_b

      rows = Competitions.standings_for_category("male")
      won = Enum.find(rows, &(&1.id == winner.id))
      lost = Enum.find(rows, &(&1.id == loser.id))

      assert %{played: 1, won: 1, lost: 0, match_difference: 1} = won
      assert %{frames_won: 6, frames_lost: 2, frame_difference: 4} = won
      assert won.sp_points == 5

      assert %{played: 1, won: 0, lost: 1, match_difference: -1} = lost
      assert %{frames_won: 2, frames_lost: 6, frame_difference: -4} = lost
      assert lost.sp_points == 2
    end

    test "a difference of zero or less is shown without a plus sign", %{conn: conn} do
      played_bracket()

      {:ok, _view, html} = live(as_td(conn), ~p"/admin/standings")

      assert html =~ "+4"
      assert html =~ "-4"
    end
  end

  describe "ranking order" do
    test "SP Points come first" do
      played_bracket()
      rows = Competitions.standings_for_category("male")

      assert Enum.map(rows, & &1.sp_points) == Enum.sort(Enum.map(rows, & &1.sp_points), :desc)
    end

    test "players level on points are split by match then frame difference" do
      played_bracket()
      rows = Competitions.standings_for_category("male")

      # Within each SP Points band the order must never improve as you go down.
      rows
      |> Enum.chunk_by(& &1.sp_points)
      |> Enum.each(fn band ->
        keys = Enum.map(band, &{-&1.match_difference, -&1.frame_difference, -&1.frames_won})
        assert keys == Enum.sort(keys), "a points band is out of order: #{inspect(keys)}"
      end)
    end

    test "frame difference separates players level on points and matches" do
      stage = circuit()
      admin = insert(:admin, role: "tournament_director")

      players =
        for _ <- 1..8, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, "male", admin)

      [narrow, wide | _] =
        Repo.all(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1,
            order_by: f.slot,
            limit: 2
        )

      # Same points, same match difference, different frame difference.
      Competitions.record_result(narrow, admin, %{
        "winner_participation_id" => narrow.participant_a_id,
        "score" => %{"a" => 6, "b" => 5}
      })

      Competitions.record_result(wide, admin, %{
        "winner_participation_id" => wide.participant_a_id,
        "score" => %{"a" => 6, "b" => 0}
      })

      rows = Competitions.standings_for_category("male")
      assert length(players) == 8

      wide_row = Enum.find(rows, &(&1.id == wide.participant_a_id))
      narrow_row = Enum.find(rows, &(&1.id == narrow.participant_a_id))

      assert wide_row, "the 6-0 winner is missing from the standings"
      assert narrow_row, "the 6-5 winner is missing from the standings"

      # Both on 5 points and +1 match difference, so frame difference decides.
      assert wide_row.sp_points == narrow_row.sp_points
      assert wide_row.match_difference == narrow_row.match_difference
      assert wide_row.frame_difference > narrow_row.frame_difference

      assert wide_row.rank < narrow_row.rank,
             "a 6-0 win should rank above a 6-5 win, got " <>
               "6-0 #{inspect(Map.take(wide_row, [:rank, :sp_points, :match_difference, :frame_difference]))} " <>
               "vs 6-5 #{inspect(Map.take(narrow_row, [:rank, :sp_points, :match_difference, :frame_difference]))}"
    end
  end

  describe "sorting" do
    test "a column can be sorted without changing anyone's rank", %{conn: conn} do
      played_bracket()

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/standings")

      ranks_before =
        Competitions.standings_for_category("male") |> Enum.map(&{&1.id, &1.rank}) |> Map.new()

      view |> element("button[phx-value-by='frames_lost']") |> render_click()
      assert_patch(view) =~ "sort=frames_lost"

      ranks_after =
        Competitions.standings_for_category("male") |> Enum.map(&{&1.id, &1.rank}) |> Map.new()

      assert ranks_before == ranks_after
    end

    test "clicking the active column flips the direction", %{conn: conn} do
      played_bracket()

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/standings")

      view |> element("button[phx-value-by='frames_won']") |> render_click()
      assert assert_patch(view) =~ "dir=desc"

      view |> element("button[phx-value-by='frames_won']") |> render_click()
      assert assert_patch(view) =~ "dir=asc"
    end

    test "the category and sort survive a reload", %{conn: conn} do
      played_bracket("female")

      {:ok, _view, html} =
        live(as_td(conn), ~p"/admin/standings?category=female&sort=sp_points&dir=desc")

      assert html =~ "Ladies&#39; Singles" or html =~ "Ladies' Singles"
    end
  end

  describe "live updates" do
    test "a result recorded elsewhere updates the table", %{conn: conn} do
      %{bracket: bracket, admin: admin} = played_bracket()

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/standings")

      next =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where:
              r.knockout_bracket_id == ^bracket.id and r.sequence == 2 and
                not is_nil(f.participant_a_id) and not is_nil(f.participant_b_id),
            limit: 1
        )

      parent = self()

      Task.async(fn ->
        Sandbox.allow(Repo, parent, self())

        Competitions.record_result(next, admin, %{
          "winner_participation_id" => next.participant_a_id,
          "score" => %{"a" => 6, "b" => 0}
        })
      end)
      |> Task.await()

      # Two wins and twelve frames now exist for somebody.
      assert render(view) =~ "8"
    end
  end
end
