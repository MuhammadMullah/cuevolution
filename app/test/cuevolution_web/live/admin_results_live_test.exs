defmodule CuevolutionWeb.AdminResultsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions

  defp log_in_admin(conn, attrs \\ []) do
    admin =
      case Keyword.fetch(attrs, :id) do
        {:ok, id} -> Cuevolution.Repo.get!(Cuevolution.Accounts.Admin, id)
        :error -> insert(:admin, attrs)
      end

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

  test "a venue rep with no venue assigned sees why the page is empty instead of a silent blank",
       %{conn: conn} do
    conn = log_in_admin(conn, role: "venue_representative", venue_id: nil)
    {:ok, _view, html} = live(conn, ~p"/admin/results")

    assert html =~ "not assigned to a venue yet"
  end

  test "a regional coordinator with no region assigned sees why the page is empty", %{conn: conn} do
    conn = log_in_admin(conn, role: "regional_coordinator", region_id: nil)
    {:ok, _view, html} = live(conn, ~p"/admin/results")

    assert html =~ "not assigned to a region yet"
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

  test "venue representative only sees and submits results for their venue", %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])

    other_fixture =
      insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])

    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ Competitions.participant_name(fixture.participant_a)
    refute html =~ Competitions.participant_name(other_fixture.participant_a)

    view |> element("[phx-click='select_fixture']") |> render_click(%{"id" => fixture.id})

    html =
      view
      |> form("form[phx-submit='record_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_a_id}
      })
      |> render_submit()

    assert html =~ "Pending approval"

    assert Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id).status ==
             "completed"
  end

  test "a venue rep can correct their own result before approval, but not after", %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    {:ok, _result} =
      Competitions.record_result(fixture, rep, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view |> element("button", "Played / Correct") |> render_click()
    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})

    assert html =~ "Correct result"
    refute has_element?(view, "#approve-result")

    html =
      view
      |> form("form[phx-submit='correct_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_b_id}
      })
      |> render_submit()

    assert html =~ "Result corrected."

    assert Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id).winner_participation_id ==
             fixture.participant_b_id

    director = insert(:admin, role: "tournament_director")
    {:ok, _verified} = Competitions.verify_result(Cuevolution.Repo.reload(fixture), director)

    {:ok, view, _html} = live(conn, ~p"/admin/results")
    view |> element("button", "Played / Correct") |> render_click()
    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})

    assert html =~ "Approved and final."
    refute html =~ "Correct result"
  end

  test "tournament director approval makes a submitted result final", %{conn: conn} do
    fixture = insert(:fixture)
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    {:ok, _result} =
      Competitions.record_result(fixture, rep, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Provisional results awaiting approval"
    refute html =~ "Unplayed"
    refute html =~ "Played / Correct"

    view |> element("#select-result-#{fixture.id}") |> render_click()
    html = view |> element("#approve-selected-results") |> render_click()

    assert html =~ "1 result approved."

    assert Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id).status ==
             "verified"
  end

  test "tournament director filters provisional results and approves multiple selections", %{
    conn: conn
  } do
    region = build(:region)
    venue_a = insert(:venue, region_id: region.id)
    venue_b = insert(:venue, region_id: region.id)
    fixture_a = insert(:fixture, venue_id: venue_a.id)
    fixture_b = insert(:fixture, venue_id: venue_b.id)
    admin = insert(:admin)

    {:ok, _result_a} =
      Competitions.record_result(fixture_a, admin, %{
        "winner_participation_id" => fixture_a.participant_a_id
      })

    {:ok, _result_b} =
      Competitions.record_result(fixture_b, admin, %{
        "winner_participation_id" => fixture_b.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Provisional results awaiting approval"
    assert has_element?(view, "#select-result-#{fixture_a.id}")
    assert has_element?(view, "#select-result-#{fixture_b.id}")

    html =
      view
      |> form("#result-approval-filters", %{"region_id" => region.id, "venue_id" => venue_a.id})
      |> render_change()

    assert html =~ "select-result-#{fixture_a.id}"
    refute html =~ "select-result-#{fixture_b.id}"

    _html =
      view
      |> form("#result-approval-filters", %{"region_id" => region.id, "venue_id" => ""})
      |> render_change()

    view |> element("#select-result-#{fixture_a.id}") |> render_click()
    view |> element("#select-result-#{fixture_b.id}") |> render_click()
    assert render(view) =~ "Approve selected (2)"

    html = view |> element("#approve-selected-results") |> render_click()

    assert html =~ "2 results approved."

    assert Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture_a.id).status ==
             "verified"

    assert Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture_b.id).status ==
             "verified"
  end

  test "the approval queue paginates when there are more pending results than one page",
       %{conn: conn} do
    admin = insert(:admin)
    per_page = Competitions.pending_results_per_page()

    for _ <- 1..(per_page + 1) do
      fixture = insert(:fixture)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })
    end

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Page 1 of 2"
    assert count_occurrences(html, ~s(id="select-result-)) == per_page

    html = view |> element("#approval-next-page") |> render_click()

    assert html =~ "Page 2 of 2"
    assert count_occurrences(html, ~s(id="select-result-)) == 1
  end

  defp count_occurrences(html, substring) do
    html |> String.split(substring) |> length() |> Kernel.-(1)
  end
end
