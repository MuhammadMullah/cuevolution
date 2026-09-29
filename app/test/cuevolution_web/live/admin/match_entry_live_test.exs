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

  test "venue representative can record a final score", %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M6")
    conn = log_in_admin(conn, "venue_representative")
    {:ok, view, html} = live(conn, ~p"/admin/matches/#{fixture.id}")

    assert html =~ "Record final score"

    html =
      view
      |> form("#record-final-score", %{
        "result" => %{"participant_a_score" => "3", "participant_b_score" => "2"}
      })
      |> render_submit()

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
    html = render_click(view, "verify", %{"result" => %{}})
    assert html =~ "permission to verify"
  end

  test "the verify panel shows and verifies the recorded final score",
       %{conn: conn} do
    fixture = insert(:fixture, match_id: "SP26-NBO-MS-A-R1-M8")
    rep = insert(:admin, role: "venue_representative")
    {:ok, _result} = Competitions.record_frames(fixture, rep, [:a, :a, :a, :b, :b])

    conn = log_in_admin(conn, "tournament_director")
    {:ok, view, html} = live(conn, ~p"/admin/matches/#{fixture.id}")

    assert html =~ "Awaiting verification"
    # Pre-filled from the actual recorded score, not blank.
    assert html =~ "3–2"

    html =
      view
      |> form("#verify-result", %{
        "result" => %{"participant_a_score" => "4", "participant_b_score" => "1"}
      })
      |> render_submit()

    assert html =~ "verified"

    fixture = Cuevolution.Repo.get!(Cuevolution.Competitions.Fixture, fixture.id)
    assert fixture.status == "verified"

    result = Cuevolution.Repo.get!(Cuevolution.Competitions.MatchResult, fixture.result_id)
    assert result.score["participant_a_frames"] == 4
    assert result.score["participant_b_frames"] == 1
  end
end
