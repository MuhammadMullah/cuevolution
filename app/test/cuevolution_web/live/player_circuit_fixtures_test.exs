defmodule CuevolutionWeb.PlayerCircuitFixturesTest do
  @moduledoc """
  A signed-in player sees their Circuit matches and the Circuit standings,
  the same way they see the earlier stages.
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

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  defp drawn_circuit(count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: "male")
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, "male", admin)

    fixture =
      Repo.one!(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 1,
          preload: [participant_a: :player, participant_b: :player]
      )

    %{bracket: bracket, admin: admin, fixture: fixture}
  end

  describe "Circuit fixtures on the player's own page" do
    test "an unscheduled Circuit match renders without crashing", %{conn: conn} do
      %{fixture: fixture} = drawn_circuit()
      player = fixture.participant_a.player

      {:ok, _view, html} = live(log_in_player(conn, player), ~p"/fixtures")

      # Neither a venue nor a self-organized deadline applies to the Circuit.
      assert html =~ "To be scheduled"
      assert html =~ fixture.match_id
      assert html =~ fixture.participant_b.player.first_name
    end

    test "a scheduled Circuit match shows its time without a venue", %{conn: conn} do
      %{fixture: fixture, admin: admin} = drawn_circuit()
      player = fixture.participant_a.player

      {:ok, _} =
        Competitions.schedule_bracket_fixture(fixture, admin, %{
          "date" => Date.to_iso8601(Date.add(Competitions.today_in_eat(), 1)),
          "time" => "14:30"
        })

      {:ok, _view, html} = live(log_in_player(conn, player), ~p"/fixtures")

      assert html =~ "14:30"
      assert html =~ "Venue to be confirmed"
    end

    test "a recorded Circuit result appears without needing verification", %{conn: conn} do
      %{fixture: fixture, admin: admin} = drawn_circuit()
      player = fixture.participant_a.player

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 3}
        })

      {:ok, _view, html} = live(log_in_player(conn, player), ~p"/fixtures")

      assert html =~ "Result recorded"
      # The Circuit stores a/b, not participant_a_frames — 0–0 would mean the
      # score shape was not understood.
      assert html =~ "6–3"
      refute html =~ "0–0"
    end

    test "the share links are offered", %{conn: conn} do
      %{fixture: fixture} = drawn_circuit()
      player = fixture.participant_a.player

      {:ok, _view, html} = live(log_in_player(conn, player), ~p"/fixtures")

      assert html =~ "Share all my matches"
      assert html =~ "/p/#{player.username}"
      assert html =~ ~s(data-url="/m/#{fixture.match_id}")
    end
  end

  describe "Circuit standings on the player's own page" do
    test "SP Points are the points column", %{conn: conn} do
      %{fixture: fixture, admin: admin} = drawn_circuit()
      player = fixture.participant_a.player

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 0}
        })

      {:ok, _view, html} = live(log_in_player(conn, player), ~p"/standings")

      assert html =~ "SP Points"
      # 2 for entering plus 3 for the win.
      row =
        Competitions.standings_for_category("male")
        |> Enum.find(&(&1.id == fixture.participant_a_id))

      assert row.sp_points == 5
      assert html =~ "#{player.first_name} #{player.last_name}"
    end
  end
end
