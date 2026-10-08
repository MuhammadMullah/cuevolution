defmodule CuevolutionWeb.AdminResultsLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions

  defp log_in_admin(conn, attrs) do
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
    venue = insert(:venue)
    conn = log_in_admin(conn, role: "venue_representative", venue_id: venue.id)
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
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
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

  test "recording a result from frame scores alone derives the winner, no radio pick needed",
       %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view |> element("[phx-click='select_fixture']") |> render_click(%{"id" => fixture.id})

    html =
      view
      |> form("form[phx-submit='record_result']", %{
        "result" => %{"participant_a_frames" => "1", "participant_b_frames" => "4"}
      })
      |> render_submit()

    assert html =~ "Result recorded."

    result =
      Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id)

    assert result.winner_participation_id == fixture.participant_b_id
  end

  test "recording a result with neither a winner nor a score shows an error instead of crashing",
       %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view |> element("[phx-click='select_fixture']") |> render_click(%{"id" => fixture.id})

    html =
      view
      |> form("form[phx-submit='record_result']", %{"result" => %{}})
      |> render_submit()

    assert html =~ "Pick a winner or enter the frame score."
    refute Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id).result_id
  end

  test "recording a result with tied frame scores is rejected", %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    conn = log_in_admin(conn, id: rep.id, role: rep.role, venue_id: rep.venue_id)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view |> element("[phx-click='select_fixture']") |> render_click(%{"id" => fixture.id})

    html =
      view
      |> form("form[phx-submit='record_result']", %{
        "result" => %{"participant_a_frames" => "3", "participant_b_frames" => "3"}
      })
      |> render_submit()

    assert html =~ "can&#39;t be tied"
    refute Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id).result_id
  end

  test "correcting just the frame score flips the winner automatically, even with a stale radio pick",
       %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    admin = insert(:admin)

    {:ok, _result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ "may affect standings"

    html =
      view
      |> form("form[phx-submit='correct_result']", %{
        "result" => %{
          # Deliberately the *wrong* (stale) winner — the scores below favor
          # participant_b, so the score must win regardless of this.
          "winner_participation_id" => fixture.participant_a_id,
          "participant_a_frames" => "2",
          "participant_b_frames" => "5"
        }
      })
      |> render_submit()

    assert html =~ "Result corrected."

    fixture = Cuevolution.Repo.preload(fixture, [], force: true)

    result =
      Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id)

    assert result.winner_participation_id == fixture.participant_b_id
    assert result.score == %{"participant_a_frames" => 2, "participant_b_frames" => 5}

    # Reopening shows the just-saved score, not a blank form.
    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ ~s(name="result[participant_a_frames]" value="2")
    assert html =~ ~s(name="result[participant_b_frames]" value="5")
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

    # `record_points/3` requires `:record_results` (Tournament Director has
    # only `:approve_results` — see `Admin.permissions/0`), so initial points
    # entry stays with the recorder/Super Admin; a Tournament Director can
    # still correct an existing entry (`correct_points/3`, gated on
    # `:approve_results`). Reuse the super admin who recorded the result to
    # exercise the entry form here.
    conn = log_in_admin(conn, id: admin.id, role: admin.role)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

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

  test "a tournament director can open a single pending result, correct it, then approve just that one",
       %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    {:ok, _result} =
      Competitions.record_result(fixture, rep, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ "Correct result"

    html =
      view
      |> form("form[phx-submit='correct_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_b_id}
      })
      |> render_submit()

    assert html =~ "Result corrected."
    refute has_element?(view, "#approve-result")

    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ "Approve and finalize result"

    html = view |> element("#approve-result") |> render_click()

    assert html =~ "Result approved and finalized."
    refute html =~ "select-result-#{fixture.id}"

    updated_fixture = Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id)
    assert updated_fixture.status == "verified"

    result =
      Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id)

    assert result.winner_participation_id == fixture.participant_b_id
  end

  test "a tournament director can open the Approved tab and correct an already-verified result",
       %{conn: conn} do
    fixture = insert(:fixture) |> Cuevolution.Repo.preload([:participant_a, :participant_b])
    rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

    {:ok, _result} =
      Competitions.record_result(fixture, rep, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    super_admin = insert(:admin)
    {:ok, _verified} = Competitions.verify_result(Cuevolution.Repo.reload(fixture), super_admin)

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, html} = live(conn, ~p"/admin/results")

    assert html =~ "Pending approval"
    assert html =~ "Approved"

    html = view |> element("button", "Approved") |> render_click()
    assert html =~ "Already-approved results"
    assert has_element?(view, "[phx-click='select_played'][phx-value-id='#{fixture.id}']")

    html = view |> element("[phx-click='select_played']") |> render_click(%{"id" => fixture.id})
    assert html =~ "Approved and final."
    assert html =~ "Correct result"

    html =
      view
      |> form("form[phx-submit='correct_result']", %{
        "result" => %{"winner_participation_id" => fixture.participant_b_id}
      })
      |> render_submit()

    assert html =~ "Result corrected."

    result =
      Cuevolution.Repo.get_by!(Cuevolution.Competitions.MatchResult, fixture_id: fixture.id)

    assert result.winner_participation_id == fixture.participant_b_id
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

  test "tournament director searches the approval queue by player username or name", %{
    conn: conn
  } do
    findable_player = insert(:player, username: "findable-rep")
    pa = insert(:stage_participation, player_id: findable_player.id)
    findable_fixture = insert(:fixture, participant_a_id: pa.id)
    other_fixture = insert(:fixture)
    admin = insert(:admin)

    {:ok, _result_a} =
      Competitions.record_result(findable_fixture, admin, %{
        "winner_participation_id" => pa.id
      })

    {:ok, _result_b} =
      Competitions.record_result(other_fixture, admin, %{
        "winner_participation_id" => other_fixture.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    html =
      view
      |> form("#approval-search-form", %{"search" => %{"term" => "findable"}})
      |> render_change()

    assert html =~ "select-result-#{findable_fixture.id}"
    refute html =~ "select-result-#{other_fixture.id}"

    html = view |> element("button[phx-click='clear_approval_search']") |> render_click()

    assert html =~ "select-result-#{other_fixture.id}"
  end

  test "the Clear filters button in the filters panel resets region/venue filters", %{
    conn: conn
  } do
    region = build(:region)
    venue = insert(:venue, region_id: region.id)
    fixture = insert(:fixture, venue_id: venue.id)
    other_fixture = insert(:fixture)
    admin = insert(:admin)

    {:ok, _result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => fixture.participant_a_id
      })

    {:ok, _other_result} =
      Competitions.record_result(other_fixture, admin, %{
        "winner_participation_id" => other_fixture.participant_a_id
      })

    director = insert(:admin, role: "tournament_director")
    conn = log_in_admin(conn, id: director.id, role: director.role)
    {:ok, view, _html} = live(conn, ~p"/admin/results")

    view
    |> form("#result-approval-filters", %{"region_id" => region.id, "venue_id" => venue.id})
    |> render_change()

    refute render(view) =~ "select-result-#{other_fixture.id}"

    html = view |> element("button[phx-click='clear_approval_filters']") |> render_click()

    assert html =~ "select-result-#{fixture.id}"
    assert html =~ "select-result-#{other_fixture.id}"
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
