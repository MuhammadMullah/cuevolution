defmodule CuevolutionWeb.PublicMatchLiveTest do
  @moduledoc """
  Shareable match links: `/m/<match reference>` for one match, `/p/<username>`
  for all of a player's matches. Both are public and read-only.
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

  defp drawn_bracket(category \\ "male", count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    participations =
      for _ <- 1..count do
        insert(:stage_participation, stage_id: stage.id, category: category)
      end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, category, admin)

    %{bracket: bracket, admin: admin, participations: participations}
  end

  defp first_fixture(bracket) do
    Repo.one!(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 1,
        preload: [participant_a: :player, participant_b: :player]
    )
  end

  describe "a single match link" do
    test "no sign-in is needed", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, _view, html} = live(conn, ~p"/m/#{fixture.match_id}")

      assert html =~ fixture.match_id
      assert html =~ "Upcoming"
      assert html =~ "Race to"
    end

    test "both players are named", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, _view, html} = live(conn, ~p"/m/#{fixture.match_id}")

      assert html =~ fixture.participant_a.player.first_name
      assert html =~ fixture.participant_b.player.first_name
    end

    test "it never exposes a phone number", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, _view, html} = live(conn, ~p"/m/#{fixture.match_id}")

      refute html =~ fixture.participant_a.player.mobile_number
      refute html =~ "tel:"
    end

    test "an unknown reference says so rather than crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/m/SP26-NOPE-1")

      assert html =~ "No match with that reference"
      assert html =~ "SP26-NOPE-1"
    end

    test "a live score shows as it is tapped in", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, html} = live(conn, ~p"/m/#{fixture.match_id}")
      assert html =~ "Upcoming"

      {:ok, _} = Competitions.update_live_score(fixture, admin, %{"a" => 4, "b" => 1})

      html = render(view)
      assert html =~ "Live"
      assert html =~ "4"
    end

    test "a recorded result shows as final with the winner marked", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)

      {:ok, view, _html} = live(conn, ~p"/m/#{fixture.match_id}")

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      html = render(view)
      assert html =~ "Final"
      assert html =~ "6"
      assert html =~ "2"
    end
  end

  describe "a player's matches link" do
    test "every match of that player is listed, upcoming and played", %{conn: conn} do
      %{bracket: bracket, admin: admin} = drawn_bracket()
      fixture = first_fixture(bracket)
      player = fixture.participant_a.player

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 1}
        })

      {:ok, _view, html} = live(conn, ~p"/p/#{player.username}")

      assert html =~ "#{player.first_name} #{player.last_name}"
      assert html =~ player.username
      # Their round-1 win, and the round-2 match they advanced into.
      assert html =~ "Final"
      assert html =~ ">W<" or html =~ "W\n"
    end

    test "the username lookup ignores case", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      player = first_fixture(bracket).participant_a.player

      {:ok, _view, html} = live(conn, ~p"/p/#{String.upcase(player.username)}")

      assert html =~ player.first_name
    end

    test "an unknown username says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/p/nobody-at-all")

      assert html =~ "No player with that username"
    end

    test "it never exposes a phone number", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      player = first_fixture(bracket).participant_a.player

      {:ok, _view, html} = live(conn, ~p"/p/#{player.username}")

      refute html =~ player.mobile_number
      refute html =~ "tel:"
    end

    test "each row links to that match's own page", %{conn: conn} do
      %{bracket: bracket} = drawn_bracket()
      fixture = first_fixture(bracket)
      player = fixture.participant_a.player

      {:ok, _view, html} = live(conn, ~p"/p/#{player.username}")

      assert html =~ ~s(href="/m/#{fixture.match_id}")
    end
  end
end
