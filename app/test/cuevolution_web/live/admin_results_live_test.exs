defmodule CuevolutionWeb.AdminResultsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/results")
  end

  test "shows the Unplayed/Played tabs, empty by default", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Match results"
    assert html =~ "No unplayed fixtures."

    html = view |> element("button", "Played / Correct") |> render_click()
    assert html =~ "No played fixtures yet."
  end

  test "selecting an unplayed fixture and recording a result moves it to Played", %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ Competitions.participant_name(fixture.participant_a)

    view |> element("[phx-click='select_fixture']") |> render_click(%{"id" => fixture.id})

    html =
      view
      |> form("form[phx-submit='record_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_a_id}
      })
      |> render_submit()

    assert html =~ "Result recorded."
    assert html =~ "No unplayed fixtures."

    played_fixture = Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id)
    assert played_fixture.result_id
  end

  test "correcting a played result updates the winner and shows the warning banner", %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    admin = insert(:admin)

    {:ok, _result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    html = view |> element("button", "Played / Correct") |> render_click()
    assert html =~ "Winner: #{Competitions.participant_name(fixture.participant_a)}"

    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ "may affect standings"

    html =
      view
      |> form("form[phx-submit='correct_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_b_id}
      })
      |> render_submit()

    assert html =~ "Result corrected."

    fixture = Cuevolution.Repo.preload(fixture, [], force: true)

    result =
      Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id)

    assert result.winner_participation_id == fixture.participant_b_id
  end

  test "Cuevo Points entry is offered for a Circuit-stage fixture but not a Grassroots one", %{
    conn: conn
  } do
    circuit = Cuevolution.Repo.get_by!(Cuevolution.Competitions.Stage, name: "Circuit")
    pa = insert(:stage_participation, stage_id: circuit.id, category: "male")
    pb = insert(:stage_participation, stage_id: circuit.id, category: "male")
    fixture = insert(:fixture, participant_a_id: pa.id, participant_b_id: pb.id)
    admin = insert(:admin)

    {:ok, _result} =
      Competitions.record_result(fixture, admin, %{"winner_participation_id" => pa.id})

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view |> element("button", "Played / Correct") |> render_click()
    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})

    assert html =~ "Cuevo Points"

    html =
      view
      |> form("#record-points-#{pa.id}", %{"points" => "5"})
      |> render_submit()

    assert html =~ "Points recorded."
    assert Competitions.points_total(pa.id) == 5
  end
end
