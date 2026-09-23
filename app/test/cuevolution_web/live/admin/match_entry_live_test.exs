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
    html = view |> element("#verify-result") |> render_click()
    assert html =~ "permission to verify"
  end
end
