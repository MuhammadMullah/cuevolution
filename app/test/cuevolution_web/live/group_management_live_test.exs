defmodule CuevolutionWeb.GroupManagementLiveTest do
  use CuevolutionWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Draw, Group, MatchResult, Stage}
  alias Cuevolution.Repo

  defp log_in_admin(conn) do
    admin = insert(:admin, role: "super_admin")
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp create_draw_with_players(count) do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    venue = insert(:venue, region_id: region.id)

    for _ <- 1..count do
      player = insert(:player, region_id: region.id, preferred_venue_id: venue.id, gender: "male")

      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )
    end

    {grassroots, venue}
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/groups")
  end

  describe "manual flow (Team category, and Regional stage — untouched by the auto-draw)" do
    test "creating a Team group doesn't require a venue and never creates a bracket",
         %{conn: conn} do
      regional = Repo.get_by!(Stage, name: "Regional")
      region = List.first(Accounts.list_regions())
      player = insert(:player, region_id: region.id)
      team = insert(:team, region_id: region.id, captain_id: player.id)

      insert(:stage_participation,
        stage_id: regional.id,
        region_id: region.id,
        category: "team",
        team_id: team.id,
        player_id: nil
      )

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button[phx-value-id='#{regional.id}']") |> render_click()
      html = view |> element("button", "Teams") |> render_click()
      assert html =~ team.name

      html =
        view
        |> form("form[phx-submit='create_group']", group: %{"name" => "Pool A"})
        |> render_submit()

      assert html =~ "created."
      assert html =~ "Pool A"

      group = Repo.get_by!(Group, name: "Pool A")
      assert is_nil(group.venue_id)
      refute Repo.get_by(Cuevolution.Competitions.KnockoutBracket, stage_id: regional.id)
    end

    test "assigning an unassigned Team participant moves them out of the unassigned list",
         %{conn: conn} do
      regional = Repo.get_by!(Stage, name: "Regional")
      region = List.first(Accounts.list_regions())
      player = insert(:player, region_id: region.id)
      team = insert(:team, region_id: region.id, captain_id: player.id)

      participation =
        insert(:stage_participation,
          stage_id: regional.id,
          region_id: region.id,
          category: "team",
          team_id: team.id,
          player_id: nil
        )

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")
      view |> element("button[phx-value-id='#{regional.id}']") |> render_click()
      view |> element("button", "Teams") |> render_click()

      view
      |> form("form[phx-submit='create_group']", group: %{"name" => "Pool A"})
      |> render_submit()

      group = Repo.get_by!(Group, name: "Pool A")

      view |> element("button[phx-value-id='#{group.id}']") |> render_click()

      html =
        view
        |> form("form[phx-value-group_id]", %{"participation_id" => participation.id})
        |> render_change()

      assert html =~ "Added to Pool A."
      assert html =~ "Everyone in this stage/region is already grouped."
    end
  end

  describe "Grassroots Individual Male/Female — formula-driven draw, inline on this page" do
    test "proposes a draw, the stepper live-updates group sizes, and dealing creates groups",
         %{conn: conn} do
      {_grassroots, _venue} = create_draw_with_players(8)

      conn = log_in_admin(conn)
      {:ok, view, html} = live(conn, ~p"/admin/groups")

      assert html =~ "1 · Draft"
      assert html =~ "2 · Previewed"
      assert html =~ "3 · Approved"
      assert html =~ "4 · Published"
      refute html =~ "Create group"

      html = view |> element("button", "Propose draw") |> render_click()
      assert html =~ "8 entrants → 1 group"
      assert html =~ "Group sizes: 8"

      html = view |> element("button", "+") |> render_click()
      assert html =~ "8 entrants → 2 groups"
      assert html =~ "Group sizes: 4 + 4"

      html = view |> element("button", "Deal draw") |> render_click()
      assert html =~ "Draw dealt."
      assert html =~ "Group A"
      assert html =~ "Group B"

      assert html =~ "Redraw groups (3 left)"
      html = view |> element("button", "Redraw groups (3 left)") |> render_click()
      assert html =~ "Groups reshuffled"
      assert html =~ "Redraw groups (2 left)"
    end

    test "full lifecycle: deal -> approve -> publish generates fixtures, then redraw is blocked once verified",
         %{conn: conn} do
      {_grassroots, _venue} = create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      view |> element("button", "Deal draw") |> render_click()

      html = view |> element("button", "Approve draw") |> render_click()
      assert html =~ "Approved"

      html = view |> element("button", "Publish & generate fixtures") |> render_click()
      assert html =~ "Published"

      draw = Repo.one!(Draw)
      assert draw.state == "published"

      group = Repo.get_by!(Group, draw_id: draw.id)

      # Expand the card — fixtures + progress now show.
      html = view |> element("button[phx-value-id='#{group.id}']") |> render_click()
      assert html =~ "played"
      assert html =~ "SP26-"

      # Record + verify one fixture, then confirm redraw is now blocked.
      membership =
        Repo.one!(
          from gm in Cuevolution.Competitions.GroupMembership,
            where: gm.group_id == ^group.id,
            limit: 1
        )

      participation =
        Repo.get!(Cuevolution.Competitions.StageParticipation, membership.stage_participation_id)

      fixture =
        Cuevolution.Competitions.Fixture
        |> where(
          [f],
          f.participant_a_id == ^participation.id or f.participant_b_id == ^participation.id
        )
        |> limit(1)
        |> Repo.one!()

      admin = Repo.one!(from(a in Cuevolution.Accounts.Admin))
      {:ok, _} = Competitions.record_frames(fixture, admin, [:a, :a, :a, :b, :b])
      fixture = Repo.reload!(fixture)
      {:ok, _} = Competitions.verify_result(fixture, admin)

      html = view |> element("button", "Redraw") |> render_click()
      assert html =~ "Redraw published groups"

      _html =
        view
        |> element("#redraw-reason-form")
        |> render_change(%{"reason" => "testing"})

      html = view |> element("button", "Redraw and republish") |> render_click()
      assert html =~ "results already exist"
    end

    test "redrawing a published draw with no results yet succeeds once a reason is entered",
         %{conn: conn} do
      create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      view |> element("button", "Deal draw") |> render_click()
      view |> element("button", "Approve draw") |> render_click()
      view |> element("button", "Publish & generate fixtures") |> render_click()

      draw_before = Repo.one!(Draw)

      view |> element("button", "Redraw") |> render_click()

      view
      |> element("#redraw-reason-form")
      |> render_change(%{"reason" => "wrong entrants dealt"})

      html = view |> element("button", "Redraw and republish") |> render_click()

      assert html =~ "A new draft draw was created"
      refute html =~ "reason is required"

      draws = Repo.all(Draw)
      assert length(draws) == 2
      assert Enum.any?(draws, &(&1.id == draw_before.id))
      assert Enum.any?(draws, &(&1.state == "draft" and &1.id != draw_before.id))

      # The new draw is "draft" (not nil), so the top-level branch must key
      # off its actual state rather than nil-ness, or the admin is stuck on
      # a blank screen with no Propose/Deal AND no Approve/Publish/Redraw
      # buttons (none of those three match a "draft" draw).
      assert has_element?(view, "button", "Propose draw")
      refute has_element?(view, "button", "Redraw")
    end

    test "redealing after a redraw names groups fresh — no '(2)' collision suffix", %{
      conn: conn
    } do
      create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      view |> element("button", "Deal draw") |> render_click()
      view |> element("button", "Approve draw") |> render_click()
      view |> element("button", "Publish & generate fixtures") |> render_click()

      view |> element("button", "Redraw") |> render_click()

      view
      |> element("#redraw-reason-form")
      |> render_change(%{"reason" => "wrong entrants dealt"})

      view |> element("button", "Redraw and republish") |> render_click()

      # The superseded draw's "Group A" still exists (kept for audit
      # history) — the new draw's first group must still be plain
      # "Group A", not "Group A (2)", since uniqueness is per-draw now.
      view |> element("button", "Propose draw") |> render_click()
      html = view |> element("button", "Deal draw") |> render_click()
      assert html =~ "Group A"
      refute html =~ "Group A (2)"

      new_draw = Repo.one!(from d in Draw, where: d.state == "previewed")
      new_group = Repo.get_by!(Group, draw_id: new_draw.id, name: "Group A")
      assert new_group
    end

    test "pre-publish group cards are inert — no click, no misleading 0/0 progress", %{
      conn: conn
    } do
      create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      html = view |> element("button", "Deal draw") |> render_click()

      draw = Repo.one!(Draw)
      group = Repo.get_by!(Group, draw_id: draw.id)

      membership =
        Repo.one!(
          from gm in Cuevolution.Competitions.GroupMembership,
            where: gm.group_id == ^group.id,
            limit: 1
        )

      participation =
        Repo.get!(Cuevolution.Competitions.StageParticipation, membership.stage_participation_id)
        |> Repo.preload(:player)

      player_name = "#{participation.player.first_name} #{participation.player.last_name}"

      # Reviewing the roster is the whole point of Previewed/Approved — the
      # member names must show even though the card itself isn't clickable.
      assert html =~ player_name

      # No fixtures exist until publish (FR-008) — the card must not claim
      # otherwise with a "0/0" that reads as "nothing to play" rather than
      # "not generated yet", and must not be clickable at all.
      refute html =~ "played"
      refute html =~ "0/0"
      refute has_element?(view, "button[phx-value-id='#{group.id}']")

      html = view |> element("button", "Approve draw") |> render_click()
      assert html =~ player_name
      refute html =~ "played"
      refute html =~ "0/0"
      refute has_element?(view, "button[phx-value-id='#{group.id}']")
    end

    test "published group card: expanding shows fixtures, clicking a member filters to just theirs",
         %{conn: conn} do
      create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      view |> element("button", "Deal draw") |> render_click()
      view |> element("button", "Approve draw") |> render_click()
      view |> element("button", "Publish & generate fixtures") |> render_click()

      draw = Repo.one!(Draw)
      group = Repo.get_by!(Group, draw_id: draw.id)

      membership =
        Repo.one!(
          from gm in Cuevolution.Competitions.GroupMembership,
            where: gm.group_id == ^group.id,
            limit: 1
        )

      participation =
        Repo.get!(Cuevolution.Competitions.StageParticipation, membership.stage_participation_id)

      total_fixtures = group.id |> Competitions.list_fixtures_for_group() |> length()

      html =
        view
        |> element("button[phx-value-id='#{participation.id}']")
        |> render_click()

      assert html =~ "0/#{total_fixtures} played"
      assert html =~ "SP26-"
      assert html =~ "fixtures"
      assert html =~ "Showing"
      assert html =~ "Clear"

      html = view |> element("button", "Clear") |> render_click()
      assert html =~ "All fixtures"
    end

    test "a freshly published, unplayed draw shows no premature qualifiers", %{conn: conn} do
      create_draw_with_players(4)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      view |> element("button", "Propose draw") |> render_click()
      view |> element("button", "Deal draw") |> render_click()
      view |> element("button", "Approve draw") |> render_click()
      view |> element("button", "Publish & generate fixtures") |> render_click()

      html = view |> element("button", "Group standings") |> render_click()

      refute html =~ "Close stage &amp; advance qualifiers"
      refute html =~ "qualifies from this group"
    end
  end

  describe "Group standings tab" do
    defp group_with_players(count, name) do
      grassroots = Repo.get_by!(Stage, name: "Grassroots")
      region = build(:region)
      venue = insert(:venue, region_id: region.id)

      group =
        Repo.insert!(%Group{
          stage_id: grassroots.id,
          region_id: region.id,
          venue_id: venue.id,
          category: "male",
          name: name
        })

      participants =
        for _ <- 1..count do
          participation =
            insert(:stage_participation,
              stage_id: grassroots.id,
              region_id: region.id,
              category: "male"
            )

          {:ok, _membership} = Competitions.assign_to_group(participation, group)
          participation
        end

      {group, participants, venue}
    end

    defp verified_result(group, venue, a, b, score) do
      round = insert(:round, stage_id: group.stage_id, group_id: group.id)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: a.id,
          participant_b_id: b.id,
          venue_id: venue.id
        )

      result =
        Repo.insert!(
          MatchResult.create_changeset(%MatchResult{}, %{
            fixture_id: fixture.id,
            winner_participation_id: score["winner_id"],
            score: Map.delete(score, "winner_id"),
            recorded_by_admin_id: insert(:admin).id
          })
        )

      Repo.update!(Ecto.Changeset.change(fixture, result_id: result.id, status: "verified"))
    end

    test "shows top-N and best-of-rest separately with points-per-match, and close-stage advances qualifiers",
         %{conn: conn} do
      {group_a, [a1, a2, a3], venue_a} = group_with_players(3, "Standings A")
      {group_b, [b1, b2], venue_b} = group_with_players(2, "Standings B")
      config = Competitions.get_or_create_group_config(group_a.stage_id, "male")

      {:ok, _} =
        Competitions.update_group_config(config, %{advancer_count: 1, extra_qualifier_count: 1})

      verified_result(group_a, venue_a, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 5,
        "participant_b_frames" => 0,
        "points_a" => 6,
        "points_b" => 0,
        "bonus_a" => 1,
        "bonus_b" => 0
      })

      verified_result(group_a, venue_a, a2, a3, %{
        "winner_id" => a2.id,
        "participant_a_frames" => 4,
        "participant_b_frames" => 1,
        "points_a" => 4,
        "points_b" => 1,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      verified_result(group_b, venue_b, b1, b2, %{
        "winner_id" => b1.id,
        "participant_a_frames" => 5,
        "participant_b_frames" => 0,
        "points_a" => 6,
        "points_b" => 0,
        "bonus_a" => 1,
        "bonus_b" => 0
      })

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/groups")

      # Select the region/venue this test's group actually belongs to.
      view |> element("button[phx-value-id='#{group_a.region_id}']") |> render_click()
      view |> element("button[phx-value-id='#{venue_a.id}']") |> render_click()

      html = view |> element("button", "Group standings") |> render_click()

      assert html =~ "Best of rest (cross-group)"
      assert html =~ "pts/match"

      html = view |> element("button", "Close stage & advance qualifiers") |> render_click()
      assert html =~ "Confirm advancement of every listed qualifier?"

      html = view |> element("button", "Confirm & advance") |> render_click()
      assert html =~ "Qualifiers advanced."
    end
  end
end
