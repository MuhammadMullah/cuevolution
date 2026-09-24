defmodule Cuevolution.Competitions.DrawsTest do
  use Cuevolution.DataCase, async: false

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Draw, Stage, StageGroupConfig}

  test "propose_group_sizes matches the specification examples" do
    config = %StageGroupConfig{
      target_group_size: 8,
      minimum_group_size: 6,
      minimum_entrants: 4
    }

    expected = %{
      8 => {1, [8]},
      10 => {1, [10]},
      12 => {2, [6, 6]},
      15 => {2, [8, 7]},
      17 => {2, [9, 8]},
      20 => {3, [7, 7, 6]},
      30 => {4, [8, 8, 7, 7]},
      35 => {5, [7, 7, 7, 7, 7]},
      50 => {7, [8, 7, 7, 7, 7, 7, 7]}
    }

    Enum.each(expected, fn {entrant_count, result} ->
      assert {:ok, %{group_count: group_count, sizes: sizes}} =
               Competitions.propose_group_sizes(config, entrant_count)

      assert {group_count, sizes} == result
    end)
  end

  test "draw proposal blocks a venue below the minimum entrant count" do
    config = %StageGroupConfig{
      target_group_size: 8,
      minimum_group_size: 6,
      minimum_entrants: 4
    }

    assert {:error, :below_minimum} = Competitions.propose_group_sizes(config, 3)
  end

  test "create and deal persists groups, memberships, and reproducible seed" do
    admin = insert(:admin, role: "regional_coordinator")
    stage = Repo.get_by!(Stage, name: "Grassroots")
    venue = insert(:venue)

    players =
      for _ <- 1..8 do
        player = insert(:player, region_id: venue.region_id, preferred_venue_id: venue.id)

        insert(:stage_participation,
          stage_id: stage.id,
          region_id: venue.region_id,
          category: "male",
          player_id: player.id,
          team_id: nil
        )
      end

    assert length(players) == 8

    assert {:ok, %Draw{} = draw} =
             Competitions.create_draw(
               %{stage_id: stage.id, venue_id: venue.id, category: "male"},
               admin
             )

    assert draw.state == "draft"
    assert is_binary(draw.random_seed)

    assert {:ok, groups} = Competitions.deal_draw(draw, admin, nil)
    assert length(groups) == 1
    assert Repo.aggregate(Ecto.assoc(List.first(groups), :group_memberships), :count) == 8
    assert Repo.get!(Draw, draw.id).state == "previewed"
  end

  test "publishing a dealt draw generates 28 fixtures for eight players" do
    admin = insert(:admin, role: "super_admin")
    stage = Repo.get_by!(Stage, name: "Grassroots")
    venue = insert(:venue)

    for _ <- 1..8 do
      player = insert(:player, region_id: venue.region_id, preferred_venue_id: venue.id)

      insert(:stage_participation,
        stage_id: stage.id,
        region_id: venue.region_id,
        category: "male",
        player_id: player.id,
        team_id: nil
      )
    end

    {:ok, draw} =
      Competitions.create_draw(%{stage_id: stage.id, venue_id: venue.id, category: "male"}, admin)

    {:ok, _groups} = Competitions.deal_draw(draw, admin, nil)
    previewed = Repo.get!(Draw, draw.id)
    {:ok, approved} = Competitions.advance_draw_state(previewed, admin, "approved")

    assert {:ok, %{draw: published, fixtures: fixtures}} =
             Competitions.advance_draw_state(approved, admin, "published")

    assert published.state == "published"
    assert length(fixtures) == 28
    assert Enum.all?(fixtures, &(&1.status == "scheduled"))
    assert Enum.uniq_by(fixtures, & &1.match_id) == fixtures

    assert_enqueued(
      worker: Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications,
      args: %{"draw_id" => draw.id}
    )

    assert :ok =
             perform_job(
               Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications,
               %{"draw_id" => draw.id}
             )

    notification = Repo.one!(from n in Cuevolution.Notifications.Notification, limit: 1)

    assert :ok =
             perform_job(Cuevolution.Notifications.Workers.SendEmailWorker, %{
               "notification_id" => notification.id
             })

    notification_count = Repo.aggregate(Cuevolution.Notifications.Notification, :count)

    assert :ok =
             perform_job(
               Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications,
               %{"draw_id" => draw.id}
             )

    assert Repo.aggregate(Cuevolution.Notifications.Notification, :count) == notification_count
  end

  test "publishing enforces the state machine, locks groups, and rejects a second publish" do
    admin = insert(:admin, role: "super_admin")
    {draw, _players} = create_draw_with_players(admin, 4)
    {:ok, _groups} = Competitions.deal_draw(draw, admin, nil)
    previewed = Repo.get!(Draw, draw.id)

    assert {:error, :invalid_transition} =
             Competitions.advance_draw_state(previewed, admin, "published")

    assert {:ok, approved} = Competitions.advance_draw_state(previewed, admin, "approved")

    assert {:ok, %{draw: published}} =
             Competitions.advance_draw_state(approved, admin, "published")

    assert {:error, :draw, :draw_already_published, _changes} =
             Competitions.advance_draw_state(approved, admin, "published")

    group = Repo.get_by!(Cuevolution.Competitions.Group, draw_id: published.id)

    membership =
      Repo.one!(
        from gm in Cuevolution.Competitions.GroupMembership,
          where: gm.group_id == ^group.id,
          limit: 1
      )

    participation =
      Repo.get!(Cuevolution.Competitions.StageParticipation, membership.stage_participation_id)

    assert {:error, :draw_published} = Competitions.assign_to_group(participation, group)
  end

  test "generates the expected Berger rounds and BYE distribution for an odd group" do
    admin = insert(:admin, role: "super_admin")
    {draw, _players} = create_draw_with_players(admin, 5)

    {:ok, _groups} = Competitions.deal_draw(draw, admin, nil)
    previewed = Repo.get!(Draw, draw.id)
    {:ok, approved} = Competitions.advance_draw_state(previewed, admin, "approved")

    assert {:ok, %{fixtures: fixtures}} =
             Competitions.advance_draw_state(approved, admin, "published")

    assert length(fixtures) == 10
    assert length(Enum.uniq_by(fixtures, & &1.match_id)) == 10

    round_counts =
      fixtures
      |> Enum.group_by(& &1.round_id)
      |> Map.values()
      |> Enum.map(&length/1)

    assert length(round_counts) == 5
    assert Enum.all?(round_counts, &(&1 == 2))
  end

  test "redraw reuses published entrants while preserving old fixtures and match ids" do
    admin = insert(:admin, role: "super_admin")
    {draw, _players} = create_draw_with_players(admin, 4)
    {:ok, _groups} = Competitions.deal_draw(draw, admin, nil)
    {:ok, approved} = Competitions.advance_draw_state(Repo.get!(Draw, draw.id), admin, "approved")

    {:ok, %{draw: published, fixtures: old_fixtures}} =
      Competitions.advance_draw_state(approved, admin, "published")

    assert {:ok, redrawn} = Competitions.redraw(published, admin, "Correct seeding")
    assert redrawn.state == "draft"
    assert {:ok, groups} = Competitions.deal_draw(redrawn, admin, nil)
    assert length(groups) == 1

    {:ok, approved_redraw} =
      Competitions.advance_draw_state(Repo.get!(Draw, redrawn.id), admin, "approved")

    assert {:ok, %{fixtures: new_fixtures}} =
             Competitions.advance_draw_state(approved_redraw, admin, "published")

    old_ids = MapSet.new(old_fixtures, & &1.match_id)
    new_ids = MapSet.new(new_fixtures, & &1.match_id)

    assert MapSet.disjoint?(old_ids, new_ids)
    assert Repo.get!(Draw, published.id).state == "published"
  end

  test "redraw is blocked once a fixture has a recorded outcome" do
    admin = insert(:admin, role: "super_admin")
    {draw, _players} = create_draw_with_players(admin, 4)
    {:ok, _groups} = Competitions.deal_draw(draw, admin, nil)
    {:ok, approved} = Competitions.advance_draw_state(Repo.get!(Draw, draw.id), admin, "approved")

    {:ok, %{draw: published, fixtures: [fixture | _]}} =
      Competitions.advance_draw_state(approved, admin, "published")

    Repo.update!(Ecto.Changeset.change(fixture, status: "completed"))

    assert {:error, :results_exist} = Competitions.redraw(published, admin, "Too late")
  end

  defp create_draw_with_players(admin, count) do
    stage = Repo.get_by!(Stage, name: "Grassroots")
    venue = insert(:venue)

    players =
      for _ <- 1..count do
        player =
          insert(:player,
            gender: "male",
            region_id: venue.region_id,
            preferred_venue_id: venue.id
          )

        insert(:stage_participation,
          stage_id: stage.id,
          region_id: venue.region_id,
          category: "male",
          player_id: player.id,
          team_id: nil
        )

        player
      end

    {:ok, draw} =
      Competitions.create_draw(
        %{stage_id: stage.id, venue_id: venue.id, category: "male"},
        admin
      )

    {draw, players}
  end
end
