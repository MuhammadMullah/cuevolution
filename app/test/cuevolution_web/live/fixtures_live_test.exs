defmodule CuevolutionWeb.FixturesLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Repo

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/fixtures")
  end

  test "shows the no-upcoming-fixtures empty state for a player with no fixtures", %{
    conn: conn
  } do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "My fixtures"
    assert html =~ "No upcoming fixtures"
    refute html =~ "A new draw has been published"
  end

  test "shows the no-results-yet empty state (Competitions.MatchResult doesn't exist yet)", %{
    conn: conn
  } do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "Recent results"
    assert html =~ "No matches played yet"
  end

  test "shows the same empty states for a player with a team", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "No upcoming fixtures"
    assert html =~ "No matches played yet"
  end

  test "shows a real upcoming fixture with opponent, venue, and time", %{conn: conn} do
    grassroots = Repo.get_by!(Competitions.Stage, name: "Grassroots")
    region = build(:region)
    player = insert(:player, region_id: region.id, gender: "male")

    opponent =
      insert(:player,
        region_id: region.id,
        gender: "male",
        first_name: "Kevin",
        mobile_number: "+254711223344"
      )

    mine =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    theirs =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: opponent.id
      )

    venue = insert(:venue, name: "Nairobi Sports Club", region_id: region.id)

    venue_rep =
      insert(:admin,
        role: "venue_representative",
        venue_id: venue.id,
        email: "venue.rep@cuevolution.test",
        mobile_number: "+254700123456"
      )

    player = Repo.update!(Ecto.Changeset.change(player, preferred_venue_id: venue.id))

    {:ok, group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Pool A"
      })

    Competitions.assign_to_group(mine, group)
    Competitions.assign_to_group(theirs, group)

    {:ok, round} =
      Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 1"})

    row = %{
      "category" => "male",
      "a_kind" => "player",
      "a_id" => player.id,
      "b_kind" => "player",
      "b_id" => opponent.id,
      "venue_id" => venue.id,
      "date" => "2026-09-01",
      "time" => "15:00"
    }

    assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [row])
    assert mine.id != theirs.id

    conn = log_in_player(conn, player)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "A new draw has been published"
    assert html =~ "Kevin"
    assert html =~ "+254711223344"
    assert html =~ ~s(href="tel:+254711223344")
    assert html =~ "Nairobi Sports Club"
    assert html =~ venue_rep.email
    assert html =~ venue_rep.mobile_number
    assert html =~ ~s(href="tel:#{venue_rep.mobile_number}")
    refute html =~ "Other fixtures at"
    refute html =~ "No upcoming fixtures"
  end

  test "shows upcoming fixtures from other groups at the player's venue", %{conn: conn} do
    grassroots = Repo.get_by!(Competitions.Stage, name: "Grassroots")
    region = build(:region)
    venue = insert(:venue, name: "Westlands Club", region_id: region.id)
    player = insert(:player, region_id: region.id, gender: "male", preferred_venue_id: venue.id)
    opponent = insert(:player, region_id: region.id, gender: "male", first_name: "Kevin")
    other_a = insert(:player, region_id: region.id, gender: "male", first_name: "Amina")
    other_b = insert(:player, region_id: region.id, gender: "male", first_name: "Brian")

    player_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    opponent_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: opponent.id
      )

    other_a_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: other_a.id
      )

    other_b_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: other_b.id
      )

    {:ok, group_a} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Group A"
      })

    {:ok, group_b} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Group B"
      })

    Competitions.assign_to_group(player_participation, group_a)
    Competitions.assign_to_group(opponent_participation, group_a)
    Competitions.assign_to_group(other_a_participation, group_b)
    Competitions.assign_to_group(other_b_participation, group_b)

    {:ok, round_a} =
      Competitions.create_round(%{stage_id: grassroots.id, group_id: group_a.id, name: "Round 1"})

    {:ok, round_b} =
      Competitions.create_round(%{stage_id: grassroots.id, group_id: group_b.id, name: "Round 1"})

    assert [{:ok, _fixture}] =
             Competitions.enter_fixtures(round_a, [fixture_row(player.id, opponent.id, venue.id)])

    assert [{:ok, _fixture}] =
             Competitions.enter_fixtures(round_b, [fixture_row(other_a.id, other_b.id, venue.id)])

    conn = log_in_player(conn, player)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "Other fixtures at Westlands Club"
    assert html =~ "Group B"
    assert html =~ "Amina"
    assert html =~ "Brian"
  end

  test "filters upcoming fixtures and results by stage", %{conn: conn} do
    grassroots = Repo.get_by!(Competitions.Stage, name: "Grassroots")
    round_2 = Repo.get_by!(Competitions.Stage, name: "Grassroots Round 2")
    region = build(:region)
    player = insert(:player, region_id: region.id, gender: "male")
    r1_opponent = insert(:player, region_id: region.id, gender: "male", first_name: "Kevin")
    r2_opponent = insert(:player, region_id: region.id, gender: "male", first_name: "Amina")
    venue = insert(:venue, region_id: region.id)

    r1_mine =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    r1_theirs =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: r1_opponent.id
      )

    {:ok, r1_group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Pool A"
      })

    Competitions.assign_to_group(r1_mine, r1_group)
    Competitions.assign_to_group(r1_theirs, r1_group)

    {:ok, r1_round} =
      Competitions.create_round(%{
        stage_id: grassroots.id,
        group_id: r1_group.id,
        name: "Round 1"
      })

    assert [{:ok, _}] =
             Competitions.enter_fixtures(r1_round, [
               fixture_row(player.id, r1_opponent.id, venue.id)
             ])

    # Advance the player's participation to Grassroots Round 2 in place —
    # this is exactly what `advance_to_stage`/`advance_qualifiers` do, and
    # what previously caused the Round 1 fixture above to be mislabeled
    # under the player's *new* stage instead of its own.
    r2_mine =
      Repo.update!(Ecto.Changeset.change(r1_mine, stage_id: round_2.id))

    r2_theirs =
      insert(:stage_participation,
        stage_id: round_2.id,
        region_id: region.id,
        category: "male",
        player_id: r2_opponent.id
      )

    {:ok, r2_group} =
      Competitions.create_group(%{
        stage_id: round_2.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Pool A"
      })

    Competitions.assign_to_group(r2_mine, r2_group)
    Competitions.assign_to_group(r2_theirs, r2_group)

    {:ok, r2_round} =
      Competitions.create_round(%{
        stage_id: round_2.id,
        group_id: r2_group.id,
        name: "Round 1"
      })

    assert [{:ok, _}] =
             Competitions.enter_fixtures(r2_round, [
               fixture_row(player.id, r2_opponent.id, venue.id)
             ])

    conn = log_in_player(conn, player)
    {:ok, view, html} = live(conn, ~p"/fixtures")

    # Both fixtures show up, each still tagged with the stage it was
    # actually drawn in rather than the player's current stage.
    assert html =~ "Kevin"
    assert html =~ "Amina"
    assert has_element?(view, "button", "grassroots round 2")

    html = view |> element("button", "grassroots round 2") |> render_click()

    assert html =~ "Amina"
    refute html =~ "Kevin"

    html = view |> element("button", "All stages") |> render_click()

    assert html =~ "Kevin"
    assert html =~ "Amina"
  end

  defp fixture_row(player_a_id, player_b_id, venue_id) do
    %{
      "category" => "male",
      "a_kind" => "player",
      "a_id" => player_a_id,
      "b_kind" => "player",
      "b_id" => player_b_id,
      "venue_id" => venue_id,
      "date" => "2026-09-01",
      "time" => "15:00"
    }
  end
end
