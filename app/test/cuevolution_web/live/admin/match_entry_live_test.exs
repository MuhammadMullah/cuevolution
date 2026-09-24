defmodule CuevolutionWeb.Admin.MatchEntryLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions

  defp log_in_admin(conn, role) do
    admin = insert(:admin, role: role)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "anonymous visitors are redirected", %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M5")

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/matches/#{fixture.id}")
  end

  test "venue representative can record structured frames", %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M6")
    conn = log_in_admin(conn, "venue_representative")
    {:ok, view, html} = live(conn, ~p"/admin/matches/#{fixture.id}")

    assert html =~ "Record five frames"

    for sequence <- 1..3 do
      render_click(view, "set_frame", %{"sequence" => to_string(sequence), "winner" => "a"})
    end

    for sequence <- 4..5 do
      render_click(view, "set_frame", %{"sequence" => to_string(sequence), "winner" => "b"})
    end

    html = view |> element("#record-frames") |> render_click()
    assert html =~ "Awaiting verification"

    assert Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id).status ==
             "completed"
  end

  test "venue representative cannot verify a completed result", %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M7")
    admin = insert(:admin, role: "venue_representative")
    {:ok, _result} = Competitions.record_frames(fixture, admin, [:a, :a, :a, :b, :b])

    conn = log_in_admin(conn, "venue_representative")
    {:ok, view, _html} = live(conn, ~p"/admin/matches/#{fixture.id}")
    refute has_element?(view, "#verify-result")
    html = render_click(view, "verify", %{})
    assert html =~ "permission to verify"
  end

  test "the verify panel shows the recorded frames read-only-prefilled, live score, and lets the TD correct one before verifying",
       %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M8")
    rep = insert(:admin, role: "venue_representative")
    {:ok, _result} = Competitions.record_frames(fixture, rep, [:a, :a, :a, :b, :b])

    conn = log_in_admin(conn, "regional_coordinator")
    {:ok, view, html} = live(conn, ~p"/admin/matches/#{fixture.id}")

    assert html =~ "Awaiting verification"
    # Pre-filled from the actual recorded frames, not blank — the TD sees
    # what was really played (3-2 to participant A), not a fresh form.
    assert html =~ "3–2"

    # Flip frame 5 from B to A before verifying — the TD is correcting a
    # genuine data-entry mistake, not just re-confirming blindly.
    html = render_click(view, "set_correction_frame", %{"sequence" => "5", "winner" => "a"})
    assert html =~ "4–1"

    html = view |> element("#verify-result") |> render_click()
    assert html =~ "verified"

    fixture = Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id)
    assert fixture.status == "verified"

    result = Cuevolution.Repo.get!(Cuevolution.Competitions.MatchResult, fixture.result_id)
    assert result.score["participant_a_frames"] == 4
    assert result.score["participant_b_frames"] == 1
  end
end
