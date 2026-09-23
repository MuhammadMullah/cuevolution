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
             Competitions.create_draw(%{stage_id: stage.id, venue_id: venue.id, category: "male"})

    assert draw.state == "draft"
    assert is_binary(draw.random_seed)

    assert {:ok, groups} = Competitions.deal_draw(draw)
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
      Competitions.create_draw(%{stage_id: stage.id, venue_id: venue.id, category: "male"})

    {:ok, _groups} = Competitions.deal_draw(draw)
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
  end
end
