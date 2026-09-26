defmodule CuevolutionWeb.VenueFixturesLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions.{Fixture, Stage, StageParticipation}
  alias Cuevolution.Repo

  test "venue representatives see every fixture at their venue and participant phone numbers", %{
    conn: conn
  } do
    venue = insert(:venue)
    other_venue = insert(:venue)
    stage = Cuevolution.Repo.get_by!(Stage, order: 1)

    {fixture_one, player_one, player_two} =
      venue_fixture(venue, stage, "Group A", "A-001", "+254700000001", "+254700000002")

    {_fixture_two, player_three, player_four} =
      venue_fixture(venue, stage, "Group B", "B-001", "+254700000003", "+254700000004")

    {_other_fixture, other_player_one, other_player_two} =
      venue_fixture(
        other_venue,
        stage,
        "Other venue group",
        "OTHER-001",
        "+254700000005",
        "+254700000006"
      )

    admin = insert(:admin, role: "venue_representative", venue_id: venue.id)
    conn = log_in_admin(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/venue-fixtures")

    assert has_element?(view, "#admin-sidebar")
    assert render(view) =~ venue.name
    assert render(view) =~ "Group A"
    assert render(view) =~ "Group B"
    assert render(view) =~ fixture_one.match_id
    assert render(view) =~ player_one.mobile_number
    assert render(view) =~ player_two.mobile_number
    assert render(view) =~ player_three.mobile_number
    assert render(view) =~ player_four.mobile_number
    assert render(view) =~ ~s(href="tel:#{player_one.mobile_number}")
    refute render(view) =~ other_player_one.mobile_number
    refute render(view) =~ other_player_two.mobile_number
  end

  test "unassigned venue representatives see an assignment prompt", %{conn: conn} do
    conn = log_in_admin(conn, insert(:admin, role: "venue_representative"))

    {:ok, view, _html} = live(conn, ~p"/admin/venue-fixtures")

    assert render(view) =~ "not assigned to a venue yet"
  end

  test "venue representatives can download only their venue fixtures as csv", %{conn: conn} do
    venue = insert(:venue)
    other_venue = insert(:venue)
    stage = Cuevolution.Repo.get_by!(Stage, order: 1)

    {_fixture, player_one, player_two} =
      venue_fixture(venue, stage, "Group A", "A-CSV", "+254799990001", "+254799990002")

    {_fixture, other_player_one, other_player_two} =
      venue_fixture(
        other_venue,
        stage,
        "Other group",
        "OTHER-CSV",
        "+254799990003",
        "+254799990004"
      )

    conn
    |> log_in_admin(insert(:admin, role: "venue_representative", venue_id: venue.id))
    |> get(~p"/admin/venue-fixtures/export.csv")
    |> then(fn conn ->
      assert response(conn, 200) =~ "A-CSV"
      assert response(conn, 200) =~ player_one.mobile_number
      assert response(conn, 200) =~ player_two.mobile_number
      refute response(conn, 200) =~ "OTHER-CSV"
      refute response(conn, 200) =~ other_player_one.mobile_number
      refute response(conn, 200) =~ other_player_two.mobile_number
      assert response_content_type(conn, :csv) =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="venue-fixtures-#{Date.utc_today()}.csv")
             ]
    end)
  end

  defp venue_fixture(venue, stage, group_name, match_id, mobile_one, mobile_two) do
    player_one = insert(:player, region_id: venue.region_id, mobile_number: mobile_one)
    player_two = insert(:player, region_id: venue.region_id, mobile_number: mobile_two)

    participant_one =
      %StageParticipation{
        player_id: player_one.id,
        region_id: venue.region_id,
        stage_id: stage.id,
        category: player_one.gender,
        joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    participant_two =
      %StageParticipation{
        player_id: player_two.id,
        region_id: venue.region_id,
        stage_id: stage.id,
        category: player_two.gender,
        joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    group =
      insert(:group,
        stage_id: stage.id,
        region_id: venue.region_id,
        venue_id: venue.id,
        category: player_one.gender,
        name: group_name
      )

    round = insert(:round, stage_id: stage.id, group_id: group.id)

    fixture =
      %Fixture{
        round_id: round.id,
        participant_a_id: participant_one.id,
        participant_b_id: participant_two.id,
        venue_id: venue.id,
        match_id: match_id,
        scheduled_at: ~U[2026-09-27 09:00:00Z]
      }
      |> Repo.insert!()

    {fixture, player_one, player_two}
  end

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end
end
