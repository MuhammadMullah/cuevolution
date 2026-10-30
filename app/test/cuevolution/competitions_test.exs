defmodule Cuevolution.CompetitionsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Group
  alias Cuevolution.Competitions.GroupMembership
  alias Cuevolution.Competitions.MatchResult
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig
  alias Cuevolution.Competitions.StageParticipation

  defp stage(name), do: Repo.get_by!(Stage, name: name)

  defp circuit_fixture(category) do
    circuit = stage("Circuit")
    bracket = Competitions.ensure_knockout_bracket(circuit.id, category)
    participant_a = insert(:stage_participation, stage_id: circuit.id, category: category)
    participant_b = insert(:stage_participation, stage_id: circuit.id, category: category)

    {:ok, round} =
      Competitions.create_round(%{
        stage_id: circuit.id,
        knockout_bracket_id: bracket.id,
        name: "Round of 4"
      })

    insert(:fixture,
      round_id: round.id,
      participant_a_id: participant_a.id,
      participant_b_id: participant_b.id
    )
  end

  describe "list_stages/0" do
    test "returns all 6 seeded stages in pipeline order" do
      assert Enum.map(Competitions.list_stages(), & &1.name) == [
               "Grassroots",
               "Grassroots Round 2",
               "Regional",
               "Regional Round 2",
               "Circuit",
               "Finals"
             ]
    end
  end

  describe "next_stage/1" do
    test "returns the following stage" do
      assert Competitions.next_stage(stage("Grassroots")).name == "Grassroots Round 2"
      assert Competitions.next_stage(stage("Grassroots Round 2")).name == "Regional"
      assert Competitions.next_stage(stage("Regional")).name == "Regional Round 2"
      assert Competitions.next_stage(stage("Regional Round 2")).name == "Circuit"
      assert Competitions.next_stage(stage("Circuit")).name == "Finals"
    end

    test "returns nil after Finals" do
      assert Competitions.next_stage(stage("Finals")) == nil
    end
  end

  describe "capacity_config/2" do
    test "returns nil for open stages (Grassroots, Regional)" do
      assert Competitions.capacity_config(stage("Grassroots").id, "male") == nil
      assert Competitions.capacity_config(stage("Regional").id, "team") == nil
    end

    test "returns the seeded config for capped stages" do
      config = Competitions.capacity_config(stage("Circuit").id, "male")
      assert config.capacity_limit == 128
    end
  end

  describe "advance_to_stage/3" do
    test "never rejects for an open destination stage" do
      admin = insert(:admin, role: "super_admin")
      participation = insert(:stage_participation, stage_id: stage("Grassroots").id)

      assert {:ok, updated} =
               Competitions.advance_to_stage(participation, admin, stage("Regional"))

      assert updated.stage_id == stage("Regional").id
    end

    test "accepts while under capacity and increments current_count" do
      admin = insert(:admin, role: "super_admin")
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "female")

      participation =
        insert(:stage_participation, stage_id: stage("Circuit").id, category: "female")

      assert {:ok, _updated} = Competitions.advance_to_stage(participation, admin, finals)

      assert Repo.get!(StageCapacityConfig, config.id).current_count == config.current_count + 1
    end

    test "rejects with :capacity_exceeded once the limit is reached" do
      admin = insert(:admin, role: "super_admin")
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "team")

      Repo.update_all(
        from(c in StageCapacityConfig, where: c.id == ^config.id),
        set: [current_count: config.capacity_limit]
      )

      participation =
        insert(:stage_participation,
          player_id: nil,
          team_id: insert(:team).id,
          stage_id: stage("Circuit").id,
          category: "team"
        )

      assert {:error, :capacity_exceeded} =
               Competitions.advance_to_stage(participation, admin, finals)
    end

    test "does not increment current_count on a lost/rejected advance" do
      admin = insert(:admin, role: "super_admin")
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "male")

      Repo.update_all(
        from(c in StageCapacityConfig, where: c.id == ^config.id),
        set: [current_count: config.capacity_limit]
      )

      participation =
        insert(:stage_participation, stage_id: stage("Circuit").id, category: "male")

      assert {:error, :capacity_exceeded} =
               Competitions.advance_to_stage(participation, admin, finals)

      assert Repo.get!(StageCapacityConfig, config.id).current_count == config.capacity_limit
    end

    test "rejects a regional_coordinator with :unauthorized" do
      admin = insert(:admin, role: "regional_coordinator")
      participation = insert(:stage_participation, stage_id: stage("Grassroots").id)

      assert {:error, :unauthorized} =
               Competitions.advance_to_stage(participation, admin, stage("Regional"))

      assert Repo.get!(Cuevolution.Competitions.StageParticipation, participation.id).stage_id ==
               stage("Grassroots").id
    end

    test "logs the advance in the admin action log" do
      admin = insert(:admin, role: "tournament_director")
      participation = insert(:stage_participation, stage_id: stage("Grassroots").id)

      assert {:ok, updated} =
               Competitions.advance_to_stage(participation, admin, stage("Regional"))

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          entity_id: updated.id,
          action_type: "advance_to_stage"
        )

      assert log.admin_id == admin.id
      assert log.new_value["stage_id"] == stage("Regional").id
    end
  end

  describe "bulk_advance_to_regional/3" do
    defp male_at(stage_name, region, username) do
      player = insert(:player, username: username, region_id: region.id, gender: "male")

      insert(:stage_participation,
        player_id: player.id,
        stage_id: stage(stage_name).id,
        region_id: region.id,
        category: "male"
      )
    end

    test "advances a player currently at Grassroots" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Grassroots", region, "bulkplayer1")

      assert {:ok, %{advanced: [advanced], errors: []}} =
               Competitions.bulk_advance_to_regional(["bulkplayer1"], region.id, admin)

      assert advanced.stage_id == stage("Regional").id
    end

    test "advances a player currently at Grassroots Round 2" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Grassroots Round 2", region, "bulkplayer2")

      assert {:ok, %{advanced: [advanced], errors: []}} =
               Competitions.bulk_advance_to_regional(["bulkplayer2"], region.id, admin)

      assert advanced.stage_id == stage("Regional").id
    end

    test "matches usernames case-insensitively" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Grassroots", region, "bulkplayer3")

      assert {:ok, %{advanced: [_advanced], errors: []}} =
               Competitions.bulk_advance_to_regional(["BulkPlayer3"], region.id, admin)
    end

    test "ignores blank lines and de-duplicates repeated usernames" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Grassroots", region, "bulkplayer4")

      assert {:ok, %{advanced: [_one], errors: []}} =
               Competitions.bulk_advance_to_regional(
                 ["", "bulkplayer4", "  ", "bulkplayer4"],
                 region.id,
                 admin
               )
    end

    test "is best-effort — a bad username doesn't block the rest of the batch" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Grassroots", region, "bulkplayer5")

      assert {:ok, %{advanced: [advanced], errors: [{"doesnotexist", :player_not_found}]}} =
               Competitions.bulk_advance_to_regional(
                 ["bulkplayer5", "doesnotexist"],
                 region.id,
                 admin
               )

      assert advanced.stage_id == stage("Regional").id
    end

    test "rejects a player from a different region" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      other_region = build(:region)
      male_at("Grassroots", other_region, "bulkplayer6")

      assert {:ok, %{advanced: [], errors: [{"bulkplayer6", :wrong_region}]}} =
               Competitions.bulk_advance_to_regional(["bulkplayer6"], region.id, admin)
    end

    test "rejects a player who has already moved past Grassroots" do
      admin = insert(:admin, role: "tournament_director")
      region = build(:region)
      male_at("Regional", region, "bulkplayer7")

      assert {:ok, %{advanced: [], errors: [{"bulkplayer7", :not_in_grassroots}]}} =
               Competitions.bulk_advance_to_regional(["bulkplayer7"], region.id, admin)
    end

    test "rejects a regional coordinator with :unauthorized" do
      admin = insert(:admin, role: "regional_coordinator")
      region = build(:region)

      assert {:error, :unauthorized} =
               Competitions.bulk_advance_to_regional(["anyone"], region.id, admin)
    end

    test "logs each successful advance in the admin action log" do
      admin = insert(:admin, role: "super_admin")
      region = build(:region)
      male_at("Grassroots", region, "bulkplayer8")

      assert {:ok, %{advanced: [advanced], errors: []}} =
               Competitions.bulk_advance_to_regional(["bulkplayer8"], region.id, admin)

      assert Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
               entity_id: advanced.id,
               action_type: "advance_to_stage"
             )
    end
  end

  describe "list_participations/1" do
    test "filters by stage, region, and category" do
      grassroots = stage("Grassroots")
      matching = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      insert(:stage_participation, stage_id: grassroots.id, category: "female")

      results =
        Competitions.list_participations(%{
          stage_id: grassroots.id,
          region_id: matching.region_id,
          category: "male"
        })

      assert Enum.map(results, & &1.id) == [matching.id]
    end

    test "filters by venue, matching a player's preferred venue or a team's match venue" do
      grassroots = stage("Grassroots")
      venue = insert(:venue)

      player = insert(:player, preferred_venue_id: venue.id)

      matching_player =
        insert(:stage_participation, stage_id: grassroots.id, player_id: player.id)

      team = insert(:team, match_venue_id: venue.id)

      matching_team =
        insert(:stage_participation,
          stage_id: grassroots.id,
          player_id: nil,
          team_id: team.id,
          category: "team"
        )

      insert(:stage_participation, stage_id: grassroots.id)

      results =
        Competitions.list_participations(%{stage_id: grassroots.id, venue_id: venue.id})

      assert Enum.map(results, & &1.id) |> Enum.sort() ==
               Enum.sort([matching_player.id, matching_team.id])
    end

    test "filters by search, matching player name, username, or team name" do
      grassroots = stage("Grassroots")

      player = insert(:player, first_name: "Martin", last_name: "Kihato", username: "mkihato")
      by_name = insert(:stage_participation, stage_id: grassroots.id, player_id: player.id)

      team = insert(:team, name: "Nairobi Strikers")

      by_team_name =
        insert(:stage_participation,
          stage_id: grassroots.id,
          player_id: nil,
          team_id: team.id,
          category: "team"
        )

      insert(:stage_participation, stage_id: grassroots.id)

      assert Competitions.list_participations(%{stage_id: grassroots.id, search: "kihato"})
             |> Enum.map(& &1.id) == [by_name.id]

      assert Competitions.list_participations(%{stage_id: grassroots.id, search: "strikers"})
             |> Enum.map(& &1.id) == [by_team_name.id]
    end
  end

  describe "realign_participation_regions/2" do
    test "repoints a player's participations at their new region" do
      player = insert(:player)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      new_region = build(:region)

      assert Competitions.realign_participation_regions(player.id, new_region.id) == 1
      assert Repo.get!(StageParticipation, participation.id).region_id == new_region.id
    end

    # A drawn participation's group, fixtures and results all belong to the
    # old region, so moving it across is a competition decision, not a data
    # correction — it stays put and stays reachable via "All regions".
    test "leaves a participation already dealt into a published draw alone" do
      player = insert(:player)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      drawn_group = insert(:group, draw_id: insert(:draw).id)

      insert(:group_membership,
        group_id: drawn_group.id,
        stage_participation_id: participation.id
      )

      new_region = build(:region)

      assert Competitions.realign_participation_regions(player.id, new_region.id) == 0
      assert Repo.get!(StageParticipation, participation.id).region_id == player.region_id
    end

    test "still moves an undrawn participation for a player who has another that is drawn" do
      player = insert(:player)

      drawn =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      undrawn =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      drawn_group = insert(:group, draw_id: insert(:draw).id)
      insert(:group_membership, group_id: drawn_group.id, stage_participation_id: drawn.id)

      new_region = build(:region)

      assert Competitions.realign_participation_regions(player.id, new_region.id) == 1
      assert Repo.get!(StageParticipation, undrawn.id).region_id == new_region.id
      assert Repo.get!(StageParticipation, drawn.id).region_id == player.region_id
    end

    test "is a no-op when the region already matches" do
      player = insert(:player)

      insert(:stage_participation,
        player_id: player.id,
        region_id: player.region_id,
        category: player.gender
      )

      assert Competitions.realign_participation_regions(player.id, player.region_id) == 0
    end
  end

  describe "stages_by_participant/2" do
    test "maps each player/team id to its current stage" do
      grassroots = stage("Grassroots")
      regional = stage("Regional")

      player_participation = insert(:stage_participation, stage_id: grassroots.id)
      team = insert(:team)

      team_participation =
        insert(:stage_participation,
          player_id: nil,
          team_id: team.id,
          category: "team",
          stage_id: regional.id
        )

      result =
        Competitions.stages_by_participant(
          [player_participation.player_id],
          [team_participation.team_id]
        )

      assert result[player_participation.player_id].id == grassroots.id
      assert result[team_participation.team_id].id == regional.id
    end

    test "ignores ids with no participation and never errors on empty lists" do
      assert Competitions.stages_by_participant([], []) == %{}

      player = insert(:player)
      assert Competitions.stages_by_participant([player.id], []) == %{}
    end
  end

  describe "assign_to_group/2 and create_group/1" do
    test "Grassroots groups require a venue and never create a knockout bracket" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)

      assert {:ok, group} =
               Competitions.create_group(%{
                 stage_id: stage("Grassroots").id,
                 region_id: region.id,
                 venue_id: venue.id,
                 category: "male",
                 name: "Pool A"
               })

      assert group.venue_id == venue.id
      refute Repo.get_by(Competitions.KnockoutBracket, stage_id: stage("Grassroots").id)
    end

    test "Grassroots group creation rejects a missing venue" do
      region = build(:region)

      assert {:error, changeset} =
               Competitions.create_group(%{
                 stage_id: stage("Grassroots").id,
                 region_id: region.id,
                 category: "male",
                 name: "Pool A"
               })

      assert "is required for Grassroots-stage groups" in errors_on(changeset).venue_id
    end

    test "Grassroots Round 2 groups require a venue, same as Grassroots" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)

      assert {:ok, group} =
               Competitions.create_group(%{
                 stage_id: stage("Grassroots Round 2").id,
                 region_id: region.id,
                 venue_id: venue.id,
                 category: "male",
                 name: "Pool A"
               })

      assert group.venue_id == venue.id

      assert {:error, changeset} =
               Competitions.create_group(%{
                 stage_id: stage("Grassroots Round 2").id,
                 region_id: region.id,
                 category: "male",
                 name: "Pool B"
               })

      assert "is required for Grassroots-stage groups" in errors_on(changeset).venue_id
    end

    test "Regional groups are region-scoped, no venue, and never create a knockout bracket" do
      region = build(:region)

      assert {:ok, group} =
               Competitions.create_group(%{
                 stage_id: stage("Regional").id,
                 region_id: region.id,
                 category: "male",
                 name: "Pool A"
               })

      assert is_nil(group.venue_id)
      refute Repo.get_by(Competitions.KnockoutBracket, stage_id: stage("Regional").id)
    end

    test "Regional group creation rejects a venue" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)

      assert {:error, changeset} =
               Competitions.create_group(%{
                 stage_id: stage("Regional").id,
                 region_id: region.id,
                 venue_id: venue.id,
                 category: "male",
                 name: "Pool A"
               })

      assert "must be blank outside Grassroots" in errors_on(changeset).venue_id
    end

    test "assigns a participation to a group" do
      region = build(:region)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "male",
          name: "Pool A"
        })

      participation =
        insert(:stage_participation,
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "male"
        )

      assert {:ok, _membership} = Competitions.assign_to_group(participation, group)

      assert [%{stage_participation_id: id}] =
               Competitions.list_groups(stage("Regional").id, "male", {:region_id, region.id})
               |> List.first()
               |> Map.fetch!(:group_memberships)

      assert id == participation.id
    end

    test "rejects a category mismatch between the participation and the group" do
      region = build(:region)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "male",
          name: "Pool A"
        })

      participation =
        insert(:stage_participation,
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "female"
        )

      assert {:error, :category_mismatch} = Competitions.assign_to_group(participation, group)
    end

    test "locks the team's roster the moment it's assigned to a group" do
      region = build(:region)
      team = insert(:team, region_id: region.id)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "team",
          name: "Pool A"
        })

      participation =
        insert(:stage_participation,
          player_id: nil,
          team_id: team.id,
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "team"
        )

      refute Repo.get!(Cuevolution.Teams.Team, team.id).roster_locked_at

      assert {:ok, _membership} = Competitions.assign_to_group(participation, group)

      assert Repo.get!(Cuevolution.Teams.Team, team.id).roster_locked_at
    end

    test "doesn't touch any team when the participation is an individual player" do
      region = build(:region)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "male",
          name: "Pool A"
        })

      participation =
        insert(:stage_participation,
          stage_id: stage("Regional").id,
          region_id: region.id,
          category: "male"
        )

      assert {:ok, _membership} = Competitions.assign_to_group(participation, group)
    end
  end

  describe "close_group_stage/5" do
    defp cgs_group_with_players(count, name, venue) do
      grassroots = stage("Grassroots")
      region = build(:region)

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

      {group, participants}
    end

    defp cgs_verified_result(group, venue, participant_a, participant_b, score) do
      round = insert(:round, stage_id: group.stage_id, group_id: group.id)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: participant_a.id,
          participant_b_id: participant_b.id,
          venue_id: venue.id
        )

      result =
        Repo.insert!(
          MatchResult.create_changeset(
            %MatchResult{},
            %{
              fixture_id: fixture.id,
              winner_participation_id: score["winner_id"],
              score: Map.delete(score, "winner_id"),
              recorded_by_admin_id: insert(:admin).id
            }
          )
        )

      Repo.update!(Ecto.Changeset.change(fixture, result_id: result.id, status: "verified"))
    end

    defp cgs_double_walkover(group, venue, participant_a, participant_b) do
      round = insert(:round, stage_id: group.stage_id, group_id: group.id)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: participant_a.id,
          participant_b_id: participant_b.id,
          venue_id: venue.id,
          status: "walkover",
          walkover_kind: "double"
        )

      result =
        Repo.insert!(%MatchResult{
          fixture_id: fixture.id,
          winner_participation_id: nil,
          score: %{
            "points_a" => 0,
            "points_b" => 0,
            "walkover" => true,
            "walkover_kind" => "double"
          }
        })

      Repo.update!(Ecto.Changeset.change(fixture, result_id: result.id))
    end

    test "a group where nobody played contributes no top-N qualifiers, even past the deadline" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      {live_group, [a1, a2]} = cgs_group_with_players(2, "Live", venue)
      {dead_group, [x, y]} = cgs_group_with_players(2, "Dead", venue)

      cgs_verified_result(live_group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      # Nobody ever played in the dead group — this is what the deadline
      # worker produces once the completion deadline passes unplayed.
      cgs_double_walkover(dead_group, venue, x, y)

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      expected_ids = [a1.id]

      assert {:ok, [advanced]} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 expected_ids
               )

      assert advanced.id == a1.id
      assert advanced.stage_id == stage("Grassroots Round 2").id

      # x and y were never touched — nobody in the dead group earned a slot.
      refute Repo.get!(StageParticipation, x.id).stage_id ==
               stage("Grassroots Round 2").id

      refute Repo.get!(StageParticipation, y.id).stage_id ==
               stage("Grassroots Round 2").id
    end

    test "lets the admin manually confirm someone with no recorded result in a final group, and tags it in the audit log" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      # The group is final (a double walkover closes it without a deadline),
      # but nobody in it ever actually played — this is the "venue finished
      # playing, results just aren't typed in yet" case.
      {dead_group, [x, y]} = cgs_group_with_players(2, "Dead", venue)
      cgs_double_walkover(dead_group, venue, x, y)

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      assert {:ok, [advanced]} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [x.id]
               )

      assert advanced.id == x.id
      assert advanced.stage_id == stage("Grassroots Round 2").id

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "advance_to_stage",
          entity_id: x.id
        )

      assert log.new_value["result_recorded"] == false
    end

    test "still rejects a participant from a group that isn't final at all" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      {_live_group, [a1, _a2]} = cgs_group_with_players(2, "Live", venue)

      grassroots = stage("Grassroots")

      assert {:error, :invalid_qualifiers} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id]
               )
    end

    test "an advance with a recorded result is never tagged result_recorded: false" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      {group, [a1, a2]} = cgs_group_with_players(2, "Played", venue)

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      assert {:ok, [_advanced]} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id]
               )

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "advance_to_stage",
          entity_id: a1.id
        )

      refute Map.has_key?(log.new_value, "result_recorded")
    end

    test "an admin can manually substitute a played participant who ranked below the cutoff" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      {group, [a1, a2, a3]} = cgs_group_with_players(3, "Manual Substitute", venue)

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      cgs_verified_result(group, venue, a2, a3, %{
        "winner_id" => a2.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      # a1 is the automatic top-1; manually swap in a3 (played, but ranked
      # below the cutoff) instead of a1.
      assert {:ok, advanced} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a3.id]
               )

      assert Enum.map(advanced, & &1.id) == [a3.id]
      refute Repo.get!(StageParticipation, a1.id).stage_id == stage("Grassroots Round 2").id
    end

    test "rejects a participant from a different venue's final group" do
      venue_a = insert(:venue, region_id: build(:region).id)
      venue_b = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      {group_a, [a1, a2]} = cgs_group_with_players(2, "Venue A Group", venue_a)
      {group_b, [b1, b2]} = cgs_group_with_players(2, "Venue B Group", venue_b)

      cgs_verified_result(group_a, venue_a, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      cgs_verified_result(group_b, venue_b, b1, b2, %{
        "winner_id" => b1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      # Closing venue_a can't be used to sneak in venue_b's qualifier.
      assert {:error, :invalid_qualifiers} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue_a.id},
                 admin,
                 [a1.id, b1.id]
               )

      refute Repo.get!(StageParticipation, b1.id).stage_id == stage("Grassroots Round 2").id
    end

    test "advances from Grassroots Round 2 into Regional" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      round_2 = stage("Grassroots Round 2")

      group =
        Repo.insert!(%Group{
          stage_id: round_2.id,
          region_id: venue.region_id,
          venue_id: venue.id,
          category: "male",
          name: "GR2 Pool"
        })

      [a1, a2] =
        for _ <- 1..2 do
          participation =
            insert(:stage_participation,
              stage_id: round_2.id,
              region_id: venue.region_id,
              category: "male"
            )

          {:ok, _} = Competitions.assign_to_group(participation, group)
          participation
        end

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      config = Competitions.get_or_create_group_config(round_2.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      assert {:ok, [advanced]} =
               Competitions.close_group_stage(
                 round_2.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id]
               )

      assert advanced.id == a1.id
      assert advanced.stage_id == stage("Regional").id
    end

    defp regional_group_with_result(region) do
      regional = stage("Regional")

      group =
        Repo.insert!(%Group{
          stage_id: regional.id,
          region_id: region.id,
          category: "male",
          name: "Capacity Test"
        })

      [p1, p2] =
        for _ <- 1..2 do
          player = insert(:player, region_id: region.id)

          participation =
            insert(:stage_participation,
              player_id: player.id,
              stage_id: regional.id,
              region_id: region.id,
              category: "male"
            )

          {:ok, _} = Competitions.assign_to_group(participation, group)
          participation
        end

      venue = insert(:venue, region_id: region.id)
      round = insert(:round, stage_id: regional.id, group_id: group.id)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p2.id,
          venue_id: venue.id
        )

      result =
        Repo.insert!(
          MatchResult.create_changeset(%MatchResult{}, %{
            fixture_id: fixture.id,
            winner_participation_id: p1.id,
            score: %{"participant_a_frames" => 3, "participant_b_frames" => 0},
            recorded_by_admin_id: insert(:admin).id
          })
        )

      Repo.update!(Ecto.Changeset.change(fixture, result_id: result.id, status: "verified"))

      {group, p1, p2}
    end

    test "advances a batch together into Regional Round 2, an uncapped holding stage" do
      region = build(:region)
      admin = insert(:admin, role: "super_admin")
      regional = stage("Regional")
      regional_round_2 = stage("Regional Round 2")
      {_group, p1, p2} = regional_group_with_result(region)

      config = Competitions.get_or_create_group_config(regional.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 2})

      # "Regional Round 2" is a pure holding stage (no groups/matches yet —
      # Phase 2 of the regional restructure builds its bracket later) and
      # intentionally has no `StageCapacityConfig` row, so this advance is
      # always uncapped regardless of batch size.
      assert {:ok, advanced} =
               Competitions.close_group_stage(
                 regional.id,
                 "male",
                 {:region_id, region.id},
                 admin,
                 [p1.id, p2.id]
               )

      assert length(advanced) == 2
      assert Repo.get!(StageParticipation, p1.id).stage_id == regional_round_2.id
      assert Repo.get!(StageParticipation, p2.id).stage_id == regional_round_2.id
    end

    test "refuses the whole batch, advancing nobody, when one participant is tournament-ineligible" do
      region = build(:region)
      admin = insert(:admin, role: "super_admin")
      regional = stage("Regional")
      {_group, p1, p2} = regional_group_with_result(region)

      # Backdate p2's player past the cutoff with no override — ineligible.
      p2_player = Repo.get!(Cuevolution.Accounts.Player, p2.player_id)

      Repo.update!(Ecto.Changeset.change(p2_player, inserted_at: ~N[2026-10-01 00:00:00]))

      config = Competitions.get_or_create_group_config(regional.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 2})

      assert {:error, :registration_closed} =
               Competitions.close_group_stage(
                 regional.id,
                 "male",
                 {:region_id, region.id},
                 admin,
                 [p1.id, p2.id]
               )

      refute Repo.get!(StageParticipation, p1.id).stage_id == stage("Regional Round 2").id
      refute Repo.get!(StageParticipation, p2.id).stage_id == stage("Regional Round 2").id
    end

    test "a group with an unresolved fixture isn't closable before the deadline, but is after" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      grassroots = stage("Grassroots")

      {group, [a1, a2, a3, a4]} = cgs_group_with_players(4, "Partial", venue)

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      # a3 vs a4 never gets played — stays "scheduled".
      round = insert(:round, stage_id: group.stage_id, group_id: group.id)

      insert(:fixture,
        round_id: round.id,
        participant_a_id: a3.id,
        participant_b_id: a4.id,
        venue_id: venue.id
      )

      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      assert Competitions.final_groups(grassroots.id, "male", {:venue_id, venue.id}) == []

      assert {:error, :invalid_qualifiers} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id]
               )

      {:ok, _} =
        Competitions.set_stage_deadline(admin, grassroots, Date.add(Date.utc_today(), -2))

      assert [%{id: group_id}] =
               Competitions.final_groups(grassroots.id, "male", {:venue_id, venue.id})

      assert group_id == group.id

      # a1 (the only one who actually played and won) can now advance —
      # a3/a4 still can't, since neither of them ever played.
      assert {:ok, [advanced]} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id]
               )

      assert advanced.id == a1.id
      refute Repo.get!(StageParticipation, a3.id).stage_id == stage("Grassroots Round 2").id
      refute Repo.get!(StageParticipation, a4.id).stage_id == stage("Grassroots Round 2").id
    end
  end

  describe "search_eligible_qualifiers/4" do
    test "returns both played and unplayed members of a final group, flagged accordingly" do
      venue = insert(:venue, region_id: build(:region).id)

      {group, [a1, a2]} = cgs_group_with_players(2, "Dead", venue)
      cgs_double_walkover(group, venue, a1, a2)
      a1 = Repo.preload(a1, :player)

      results =
        Competitions.search_eligible_qualifiers(
          group.stage_id,
          "male",
          {:venue_id, venue.id},
          a1.player.first_name
        )

      assert [%{participation: found, played?: false}] = results
      assert found.id == a1.id
    end

    test "flags a played member as played?: true" do
      venue = insert(:venue, region_id: build(:region).id)
      {group, [a1, a2]} = cgs_group_with_players(2, "Played", venue)

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      a1 = Repo.preload(a1, :player)

      assert [%{participation: found, played?: true}] =
               Competitions.search_eligible_qualifiers(
                 group.stage_id,
                 "male",
                 {:venue_id, venue.id},
                 a1.player.first_name
               )

      assert found.id == a1.id
    end

    test "never returns a member of a group that isn't final yet" do
      venue = insert(:venue, region_id: build(:region).id)
      {group, [a1, _a2]} = cgs_group_with_players(2, "Live", venue)
      a1 = Repo.preload(a1, :player)

      assert Competitions.search_eligible_qualifiers(
               group.stage_id,
               "male",
               {:venue_id, venue.id},
               a1.player.first_name
             ) == []
    end
  end

  describe "mark_venue_ready_early/4 and unmark_venue_ready_early/4" do
    test "unlocks final_groups/close_group_stage for just this venue, before the deadline" do
      venue = insert(:venue, region_id: build(:region).id)
      other_venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")

      # 3 players: a1 vs a2 is verified, but a3's match never happened —
      # that unplayed fixture is what keeps the group non-final until the
      # override kicks in (mirrors the deadline-based test above).
      {group, [a1, a2, a3]} = cgs_group_with_players(3, "Ready Early", venue)
      {other_group, [b1, b2]} = cgs_group_with_players(2, "Still Playing", other_venue)

      grassroots = stage("Grassroots")

      cgs_verified_result(group, venue, a1, a2, %{
        "winner_id" => a1.id,
        "participant_a_frames" => 3,
        "participant_b_frames" => 0,
        "points_a" => 3,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

      round = insert(:round, stage_id: grassroots.id, group_id: group.id)

      insert(:fixture,
        round_id: round.id,
        participant_a_id: a2.id,
        participant_b_id: a3.id,
        venue_id: venue.id
      )

      other_round = insert(:round, stage_id: grassroots.id, group_id: other_group.id)

      insert(:fixture,
        round_id: other_round.id,
        participant_a_id: b1.id,
        participant_b_id: b2.id,
        venue_id: other_venue.id
      )

      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 1})

      refute Competitions.venue_marked_ready_early?(grassroots.id, "male", {:venue_id, venue.id})
      assert Competitions.final_groups(grassroots.id, "male", {:venue_id, venue.id}) == []

      assert {:ok, _} =
               Competitions.mark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      assert Competitions.venue_marked_ready_early?(grassroots.id, "male", {:venue_id, venue.id})

      assert [%{id: group_id}] =
               Competitions.final_groups(grassroots.id, "male", {:venue_id, venue.id})

      assert group_id == group.id

      # The other venue's still-mid-play group is untouched by this venue's
      # override.
      assert Competitions.final_groups(grassroots.id, "male", {:venue_id, other_venue.id}) == []

      # a3 never played, but the override unlocked their group as final, and
      # an admin who knows they actually qualified can confirm them anyway
      # — the group-membership rule is the only one still enforced here.
      assert {:ok, advanced} =
               Competitions.close_group_stage(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin,
                 [a1.id, a3.id]
               )

      assert Enum.map(advanced, & &1.id) |> Enum.sort() == Enum.sort([a1.id, a3.id])

      a3_log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "advance_to_stage",
          entity_id: a3.id
        )

      a1_log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "advance_to_stage",
          entity_id: a1.id
        )

      assert a3_log.new_value["result_recorded"] == false
      refute Map.has_key?(a1_log.new_value, "result_recorded")

      assert {:ok, _} =
               Competitions.unmark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      refute Competitions.venue_marked_ready_early?(grassroots.id, "male", {:venue_id, venue.id})
    end

    test "marking is idempotent and unmarking a venue that was never marked is a no-op" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      grassroots = stage("Grassroots")

      assert {:ok, _} =
               Competitions.mark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      assert {:ok, :already_marked} =
               Competitions.mark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      assert {:ok, _} =
               Competitions.unmark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      assert {:ok, :not_marked} =
               Competitions.unmark_venue_ready_early(grassroots.id, venue.id, "male", admin)
    end

    test "is restricted to :advance_participants" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "venue_representative")
      grassroots = stage("Grassroots")

      assert {:error, :unauthorized} =
               Competitions.mark_venue_ready_early(grassroots.id, venue.id, "male", admin)

      assert {:error, :unauthorized} =
               Competitions.unmark_venue_ready_early(grassroots.id, venue.id, "male", admin)
    end

    test "venue_marked_ready_early?/3 is always false for a region scope" do
      region = build(:region)
      grassroots = stage("Grassroots")

      refute Competitions.venue_marked_ready_early?(
               grassroots.id,
               "male",
               {:region_id, region.id}
             )
    end
  end

  describe "upload_result_sheet/6, list_result_sheets/2, and result_sheet_url/1" do
    test "stores the sheet and builds a venuename_stage_date object key" do
      venue = insert(:venue, name: "Chessmen Lounge", region_id: build(:region).id)
      admin = insert(:admin, role: "tournament_director")
      grassroots = stage("Grassroots")

      assert {:ok, result_sheet} =
               Competitions.upload_result_sheet(
                 grassroots,
                 venue,
                 admin,
                 "jpeg-bytes",
                 "image/jpeg",
                 "scan.jpg"
               )

      today = Date.to_iso8601(Date.utc_today())
      assert result_sheet.object_key == "result_sheets/chessmen-lounge_grassroots_#{today}.jpg"
      assert result_sheet.uploaded_on == Date.utc_today()
      assert result_sheet.uploaded_by_admin_id == admin.id

      assert [listed] = Competitions.list_result_sheets(grassroots.id, venue.id)
      assert listed.id == result_sheet.id
      assert Competitions.result_sheet_url(listed) =~ result_sheet.object_key
    end

    test "re-uploading the same venue/stage/day replaces the previous sheet" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "tournament_director")
      grassroots = stage("Grassroots")

      assert {:ok, first} =
               Competitions.upload_result_sheet(
                 grassroots,
                 venue,
                 admin,
                 "v1",
                 "image/jpeg",
                 "v1.jpg"
               )

      assert {:ok, second} =
               Competitions.upload_result_sheet(
                 grassroots,
                 venue,
                 admin,
                 "v2",
                 "application/pdf",
                 "v2.pdf"
               )

      assert second.id == first.id
      assert second.content_type == "application/pdf"
      assert [only] = Competitions.list_result_sheets(grassroots.id, venue.id)
      assert only.original_filename == "v2.pdf"
    end

    test "rejects anything other than jpg/jpeg/pdf" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "tournament_director")
      grassroots = stage("Grassroots")

      assert {:error, :unsupported_content_type} =
               Competitions.upload_result_sheet(
                 grassroots,
                 venue,
                 admin,
                 "bytes",
                 "image/png",
                 "scan.png"
               )
    end

    test "is restricted to :record_results" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "regional_coordinator")
      grassroots = stage("Grassroots")

      assert {:ok, _} =
               Competitions.upload_result_sheet(
                 grassroots,
                 venue,
                 admin,
                 "bytes",
                 "application/pdf",
                 "scan.pdf"
               )
    end
  end

  describe "advance_all_entrants/4" do
    defp venue_entrant(venue) do
      player =
        insert(:player,
          preferred_venue_id: venue.id,
          region_id: venue.region_id,
          tournament_eligibility_override: true,
          gender: "male"
        )

      insert(:stage_participation,
        player_id: player.id,
        stage_id: stage("Grassroots").id,
        region_id: venue.region_id,
        category: "male"
      )
    end

    test "advances everyone when the entrant count is at or below the advancer count" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      a1 = venue_entrant(venue)
      a2 = venue_entrant(venue)

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 2})

      assert {:ok, advanced} =
               Competitions.advance_all_entrants(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin
               )

      assert Enum.sort(Enum.map(advanced, & &1.id)) == Enum.sort([a1.id, a2.id])
      round_2 = stage("Grassroots Round 2")
      assert Repo.get!(StageParticipation, a1.id).stage_id == round_2.id
      assert Repo.get!(StageParticipation, a2.id).stage_id == round_2.id
    end

    test "refuses once there are more entrants than the advancer count" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      venue_entrant(venue)
      venue_entrant(venue)
      venue_entrant(venue)

      grassroots = stage("Grassroots")
      config = Competitions.get_or_create_group_config(grassroots.id, "male")
      {:ok, _} = Competitions.update_group_config(config, %{advancer_count: 2})

      assert {:error, :too_many_entrants} =
               Competitions.advance_all_entrants(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin
               )
    end

    test "refuses when there's nobody to advance" do
      venue = insert(:venue, region_id: build(:region).id)
      admin = insert(:admin, role: "super_admin")
      grassroots = stage("Grassroots")

      assert {:error, :no_entrants} =
               Competitions.advance_all_entrants(
                 grassroots.id,
                 "male",
                 {:venue_id, venue.id},
                 admin
               )
    end
  end

  describe "list_unassigned_participations/2" do
    test "excludes participations already in a group for that stage" do
      region = build(:region)
      stage_id = stage("Regional").id

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage_id,
          region_id: region.id,
          category: "male",
          name: "Pool A"
        })

      grouped =
        insert(:stage_participation, stage_id: stage_id, region_id: region.id, category: "male")

      ungrouped =
        insert(:stage_participation, stage_id: stage_id, region_id: region.id, category: "male")

      Competitions.assign_to_group(grouped, group)

      results = Competitions.list_unassigned_participations(stage_id, region.id, "male")

      assert Enum.map(results, & &1.id) == [ungrouped.id]
    end
  end

  describe "group_config/2 and update_group_config/2" do
    test "returns the seeded default for Grassroots/Regional" do
      config = Competitions.group_config(stage("Grassroots").id, "male")
      assert config.group_size == 8
      assert config.advancer_count == 2
    end

    test "returns nil for Circuit/Finals (no group format there)" do
      assert Competitions.group_config(stage("Circuit").id, "male") == nil
    end

    test "admin can update the advancer count" do
      config = Competitions.group_config(stage("Regional").id, "female")

      assert {:ok, updated} =
               Competitions.update_group_config(config, %{advancer_count: 3})

      assert updated.advancer_count == 3
    end
  end

  describe "ensure_knockout_bracket/2 and get_knockout_bracket/2" do
    test "creates a bracket on first call, reuses it on subsequent calls" do
      circuit = stage("Circuit")

      bracket = Competitions.ensure_knockout_bracket(circuit.id, "male")
      assert bracket.stage_id == circuit.id
      assert bracket.category == "male"

      assert Competitions.ensure_knockout_bracket(circuit.id, "male").id == bracket.id
      assert Competitions.get_knockout_bracket(circuit.id, "male").id == bracket.id
    end

    test "get_knockout_bracket/2 returns nil before one is started" do
      assert Competitions.get_knockout_bracket(stage("Finals").id, "team") == nil
    end
  end

  describe "create_round/1 and list_rounds_for_stage/1" do
    test "creates and lists group-stage rounds" do
      grassroots = stage("Grassroots")
      group = insert(:group, stage_id: grassroots.id)

      {:ok, round} =
        Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 1"})

      assert Competitions.list_rounds_for_stage(grassroots.id) |> Enum.map(& &1.id) == [round.id]
    end

    test "creates knockout-stage rounds tied to a bracket" do
      circuit = stage("Circuit")
      bracket = Competitions.ensure_knockout_bracket(circuit.id, "male")

      {:ok, round} =
        Competitions.create_round(%{
          stage_id: circuit.id,
          knockout_bracket_id: bracket.id,
          name: "Round of 128"
        })

      assert round.knockout_bracket_id == bracket.id
    end

    test "rejects a round with neither a group nor a bracket" do
      grassroots = stage("Grassroots")

      assert {:error, changeset} =
               Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

      assert "must set either a group or a knockout bracket" in errors_on(changeset).group_id
    end
  end

  describe "Fixture.changeset/3 same-category/same-stage cross-check (FR-006)" do
    test "rejects participants of different categories even if otherwise valid" do
      grassroots = stage("Grassroots")
      pa = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      pb = insert(:stage_participation, stage_id: grassroots.id, category: "female")
      venue = insert(:venue)
      group = insert(:group, stage_id: grassroots.id)

      {:ok, round} =
        Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 1"})

      changeset =
        Fixture.changeset(
          %Fixture{},
          %{
            round_id: round.id,
            participant_a_id: pa.id,
            participant_b_id: pb.id,
            venue_id: venue.id,
            scheduled_at: DateTime.utc_now()
          },
          %{participant_a: pa, participant_b: pb}
        )

      refute changeset.valid?
      assert "must be the same category as participant A" in errors_on(changeset).participant_b_id
    end

    test "rejects participants of different stages even if same category" do
      grassroots = stage("Grassroots")
      regional = stage("Regional")
      pa = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      pb = insert(:stage_participation, stage_id: regional.id, category: "male")
      venue = insert(:venue)
      group = insert(:group, stage_id: grassroots.id)

      {:ok, round} =
        Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 1"})

      changeset =
        Fixture.changeset(
          %Fixture{},
          %{
            round_id: round.id,
            participant_a_id: pa.id,
            participant_b_id: pb.id,
            venue_id: venue.id,
            scheduled_at: DateTime.utc_now()
          },
          %{participant_a: pa, participant_b: pb}
        )

      refute changeset.valid?
      assert "must be in the same stage as participant A" in errors_on(changeset).participant_b_id
    end
  end

  describe "enter_fixtures/2" do
    setup do
      grassroots = stage("Grassroots")
      region = build(:region)
      player_a = insert(:player, region_id: region.id, gender: "male")
      player_b = insert(:player, region_id: region.id, gender: "male")

      pa =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "male",
          player_id: player_a.id
        )

      pb =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "male",
          player_id: player_b.id
        )

      venue = insert(:venue, region_id: region.id)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: grassroots.id,
          region_id: region.id,
          venue_id: venue.id,
          category: "male",
          name: "Pool A"
        })

      Competitions.assign_to_group(pa, group)
      Competitions.assign_to_group(pb, group)

      {:ok, round} =
        Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 1"})

      row = %{
        "category" => "male",
        "a_kind" => "player",
        "a_id" => player_a.id,
        "b_kind" => "player",
        "b_id" => player_b.id,
        "venue_id" => venue.id,
        "date" => "2026-08-01",
        "time" => "14:00"
      }

      %{
        grassroots: grassroots,
        region: region,
        player_a: player_a,
        player_b: player_b,
        pa: pa,
        pb: pb,
        venue: venue,
        group: group,
        round: round,
        row: row
      }
    end

    test "creates a fixture and dispatches a fixture_assignment notification to both participants",
         %{round: round, row: row, player_a: player_a, player_b: player_b, pa: pa, pb: pb} do
      assert [{:ok, fixture}] = Competitions.enter_fixtures(round, [row])
      assert fixture.round_id == round.id
      assert fixture.participant_a_id == pa.id
      assert fixture.participant_b_id == pb.id

      notifications =
        Repo.all(
          from n in Cuevolution.Notifications.Notification,
            where: n.player_id in ^[player_a.id, player_b.id]
        )

      assert length(notifications) == 2
      assert Enum.all?(notifications, &(&1.event_type == "fixture_assignment"))
      assert_enqueued(worker: Cuevolution.Notifications.Workers.SendEmailWorker)
    end

    test "rejects a same-round duplicate pairing regardless of A/B order", %{
      round: round,
      row: row
    } do
      assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [row])

      swapped_row = %{row | "a_id" => row["b_id"], "b_id" => row["a_id"]}
      assert [{:error, changeset}] = Competitions.enter_fixtures(round, [swapped_row])
      assert "this pairing already exists in this round" in errors_on(changeset).round_id
    end

    test "accepts a legitimate cross-round rematch", %{
      round: round,
      row: row,
      grassroots: grassroots,
      group: group
    } do
      assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [row])

      {:ok, round_2} =
        Competitions.create_round(%{stage_id: grassroots.id, group_id: group.id, name: "Round 2"})

      assert [{:ok, _fixture_2}] = Competitions.enter_fixtures(round_2, [row])
    end

    test "batch entry commits valid rows and reports the specific error for a bad one", %{
      round: round,
      row: row
    } do
      bad_row = Map.put(row, "b_id", Ecto.UUID.generate())

      assert [ok_result, error_result] = Competitions.enter_fixtures(round, [row, bad_row])
      assert {:ok, _fixture} = ok_result
      assert {:error, {:participant_b, :participant_not_in_group}} = error_result
    end

    test "reports :invalid_datetime for a blank date/time", %{round: round, row: row} do
      bad_row = %{row | "date" => "", "time" => ""}
      assert [{:error, :invalid_datetime}] = Competitions.enter_fixtures(round, [bad_row])
    end

    test "enter_fixtures/2 rejects a participant who isn't a member of the round's group", %{
      round: round,
      row: row,
      grassroots: grassroots,
      region: region
    } do
      outsider =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "male"
        )

      bad_row = Map.put(row, "b_id", outsider.player_id)

      assert [{:error, {:participant_b, :participant_not_in_group}}] =
               Competitions.enter_fixtures(round, [bad_row])
    end

    test "Team-category fixtures dispatch to every roster member of both teams", %{
      region: region,
      venue: venue
    } do
      regional = stage("Regional")
      captain_a = insert(:player, region_id: region.id)
      {:ok, team_a} = Cuevolution.Teams.create_team(captain_a, %{"name" => "Team A"})
      member_a = insert(:player, region_id: region.id)
      {:ok, _} = Cuevolution.Teams.add_player_to_roster(team_a, member_a)

      captain_b = insert(:player, region_id: region.id)
      {:ok, team_b} = Cuevolution.Teams.create_team(captain_b, %{"name" => "Team B"})

      team_pa = Repo.get_by!(Cuevolution.Competitions.StageParticipation, team_id: team_a.id)
      team_pb = Repo.get_by!(Cuevolution.Competitions.StageParticipation, team_id: team_b.id)

      {:ok, team_group} =
        Competitions.create_group(%{
          stage_id: regional.id,
          region_id: region.id,
          category: "team",
          name: "Team Pool A"
        })

      Competitions.assign_to_group(team_pa, team_group)
      Competitions.assign_to_group(team_pb, team_group)

      {:ok, team_round} =
        Competitions.create_round(%{
          stage_id: regional.id,
          group_id: team_group.id,
          name: "Team Round 1"
        })

      team_row = %{
        "category" => "team",
        "a_kind" => "team",
        "a_id" => team_a.id,
        "b_kind" => "team",
        "b_id" => team_b.id,
        "venue_id" => venue.id,
        "date" => "2026-08-01",
        "time" => "14:00"
      }

      assert [{:ok, _fixture}] = Competitions.enter_fixtures(team_round, [team_row])

      team_a_player_ids = [captain_a.id, member_a.id]

      notifications =
        Repo.all(
          from n in Cuevolution.Notifications.Notification,
            where:
              n.player_id in ^(team_a_player_ids ++ [captain_b.id]) and
                n.event_type == "fixture_assignment"
        )

      assert length(notifications) == 3
    end
  end

  describe "update_fixture/2" do
    test "editable while no result exists" do
      fixture = insert(:fixture)
      new_venue = insert(:venue)

      assert {:ok, updated} =
               Competitions.update_fixture(fixture, %{
                 "venue_id" => new_venue.id,
                 "scheduled_at" => DateTime.utc_now()
               })

      assert updated.venue_id == new_venue.id
    end

    test "locked once a result exists" do
      result = insert(:match_result)
      fixture = insert(:fixture, result_id: result.id)

      assert {:error, :locked} =
               Competitions.update_fixture(fixture, %{"venue_id" => insert(:venue).id})
    end
  end

  describe "fixture_time_in_eat/1" do
    test "converts stored UTC to EAT (UTC+3)" do
      fixture = insert(:fixture, scheduled_at: ~U[2026-08-01 11:00:00Z])
      eat = Competitions.fixture_time_in_eat(fixture)

      assert eat.hour == 14
      assert eat.day == 1
    end

    test "rolls over into the next day when the offset crosses midnight" do
      fixture = insert(:fixture, scheduled_at: ~U[2026-08-01 22:00:00Z])
      eat = Competitions.fixture_time_in_eat(fixture)

      assert eat.hour == 1
      assert eat.day == 2
    end
  end

  describe "record_result/3" do
    test "records a result and links it to the fixture" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      assert {:ok, result} =
               Competitions.record_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      assert result.fixture_id == fixture.id
      assert result.winner_participation_id == fixture.participant_a_id
      assert Repo.get!(Fixture, fixture.id).result_id == result.id
    end

    test "a regional coordinator can record a result at any venue in their own region" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)
      fixture = insert(:fixture, venue_id: venue.id)
      coordinator = insert(:admin, role: "regional_coordinator", region_id: region.id)

      assert {:ok, result} =
               Competitions.record_result(fixture, coordinator, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      assert result.fixture_id == fixture.id
    end

    test "a regional coordinator cannot record a result at a venue outside their region" do
      coordinator_region = Repo.get_by!(Cuevolution.Accounts.Region, name: "Central")
      other_region = Repo.get_by!(Cuevolution.Accounts.Region, name: "Eastern")
      coordinator = insert(:admin, role: "regional_coordinator", region_id: coordinator_region.id)
      other_venue = insert(:venue, region_id: other_region.id)

      # Pin the group's region explicitly, rather than leaving it to
      # `fixture_factory`'s random region cycle — `scope_fixtures_for_admin/2`
      # also matches on the group's region (not just the venue's), so an
      # unpinned group could accidentally land on the coordinator's own
      # region and make this test pass for the wrong reason.
      group = insert(:group, region_id: other_region.id)
      round = insert(:round, stage_id: group.stage_id, group_id: group.id)

      participant_a =
        insert(:stage_participation, stage_id: group.stage_id, region_id: other_region.id)

      participant_b =
        insert(:stage_participation,
          stage_id: group.stage_id,
          region_id: other_region.id,
          category: participant_a.category
        )

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: participant_a.id,
          participant_b_id: participant_b.id,
          venue_id: other_venue.id
        )

      assert {:error, :unauthorized} =
               Competitions.record_result(fixture, coordinator, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      refute Repo.get!(Fixture, fixture.id).result_id
    end

    test "rejects a duplicate result for the same fixture" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      assert {:ok, _result} =
               Competitions.record_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      assert {:error, changeset} =
               Competitions.record_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_b_id
               })

      assert "a result has already been recorded for this fixture" in errors_on(changeset).fixture_id
    end

    test "locks both team rosters for a Team-category fixture" do
      region = build(:region)
      captain_a = insert(:player, region_id: region.id)
      {:ok, team_a} = Cuevolution.Teams.create_team(captain_a, %{"name" => "Team A"})
      captain_b = insert(:player, region_id: region.id)
      {:ok, team_b} = Cuevolution.Teams.create_team(captain_b, %{"name" => "Team B"})

      pa = Repo.get_by!(Cuevolution.Competitions.StageParticipation, team_id: team_a.id)
      pb = Repo.get_by!(Cuevolution.Competitions.StageParticipation, team_id: team_b.id)
      round = insert(:round, stage_id: pa.stage_id)
      venue = insert(:venue, region_id: region.id)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: pa.id,
          participant_b_id: pb.id,
          venue_id: venue.id
        )

      admin = insert(:admin)

      assert {:ok, _result} =
               Competitions.record_result(fixture, admin, %{"winner_participation_id" => pa.id})

      assert Repo.get!(Cuevolution.Teams.Team, team_a.id).roster_locked_at
      assert Repo.get!(Cuevolution.Teams.Team, team_b.id).roster_locked_at
    end

    test "does not lock a roster for an Individual-category fixture" do
      region = build(:region)
      captain = insert(:player, region_id: region.id)
      {:ok, team} = Cuevolution.Teams.create_team(captain, %{"name" => "Only Team"})

      fixture = insert(:fixture)
      admin = insert(:admin)

      assert {:ok, _result} =
               Competitions.record_result(fixture, admin, %{
                 "winner_participation_id" => fixture.participant_a_id
               })

      refute Repo.get!(Cuevolution.Teams.Team, team.id).roster_locked_at
    end
  end

  describe "correct_result/3" do
    test "updates the winner, captures prior_value, and logs the admin action" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert {:ok, corrected} =
               Competitions.correct_result(result, admin, %{
                 "winner_participation_id" => fixture.participant_b_id
               })

      assert corrected.winner_participation_id == fixture.participant_b_id
      assert corrected.prior_value["winner_participation_id"] == fixture.participant_a_id

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          entity_id: result.id,
          action_type: "correct_result"
        )

      assert log.prior_value["winner_participation_id"] == fixture.participant_a_id
      assert log.new_value["winner_participation_id"] == fixture.participant_b_id
    end

    test "a venue rep can correct a result for their own venue while it's not yet approved" do
      fixture = insert(:fixture)
      admin = insert(:admin)
      rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert {:ok, corrected} =
               Competitions.correct_result(result, rep, %{
                 "winner_participation_id" => fixture.participant_b_id
               })

      assert corrected.winner_participation_id == fixture.participant_b_id
    end

    test "a venue rep cannot correct a result once it has been approved" do
      fixture = insert(:fixture)
      admin = insert(:admin)
      rep = insert(:admin, role: "venue_representative", venue_id: fixture.venue_id)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      {:ok, _verified} = Competitions.verify_result(Repo.reload(fixture), admin)

      assert {:error, :already_approved} =
               Competitions.correct_result(result, rep, %{
                 "winner_participation_id" => fixture.participant_b_id
               })
    end

    test "a venue rep cannot correct a result for a fixture outside their venue" do
      fixture = insert(:fixture)
      admin = insert(:admin)
      rep = insert(:admin, role: "venue_representative", venue_id: insert(:venue).id)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert {:error, :unauthorized} =
               Competitions.correct_result(result, rep, %{
                 "winner_participation_id" => fixture.participant_b_id
               })
    end

    test "a suspended admin cannot correct a result despite an otherwise-permitted role" do
      fixture = insert(:fixture)
      admin = insert(:admin)
      suspended = insert(:admin, suspended_at: DateTime.utc_now() |> DateTime.truncate(:second))

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert {:error, :unauthorized} =
               Competitions.correct_result(result, suspended, %{
                 "winner_participation_id" => fixture.participant_b_id
               })
    end
  end

  describe "group_standings/1 and top_advancers/1" do
    setup do
      region = build(:region)
      grassroots = stage("Grassroots")
      venue = insert(:venue, region_id: region.id)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: grassroots.id,
          region_id: region.id,
          venue_id: venue.id,
          category: "male",
          name: "Pool A"
        })

      participants =
        for _ <- 1..3 do
          p =
            insert(:stage_participation,
              stage_id: grassroots.id,
              region_id: region.id,
              category: "male"
            )

          Competitions.assign_to_group(p, group)
          p
        end

      %{group: group, participants: participants, venue: venue, grassroots: grassroots}
    end

    test "ranks group members by recorded results", %{
      group: group,
      participants: [p1, p2, p3],
      venue: venue,
      grassroots: grassroots
    } do
      round = insert(:round, stage_id: grassroots.id, group_id: group.id)
      admin = insert(:admin)

      f1 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p2.id,
          venue_id: venue.id
        )

      f2 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p3.id,
          venue_id: venue.id
        )

      f3 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p2.id,
          participant_b_id: p3.id,
          venue_id: venue.id
        )

      Competitions.record_result(f1, admin, %{"winner_participation_id" => p1.id})
      Competitions.record_result(f2, admin, %{"winner_participation_id" => p1.id})
      Competitions.record_result(f3, admin, %{"winner_participation_id" => p2.id})

      standings = Competitions.group_standings(group)

      assert Enum.map(standings, & &1.participant_id) == [p1.id, p2.id, p3.id]
    end

    test "top_advancers/1 returns the configured advancer_count cutoff", %{
      group: group,
      participants: [p1, p2, p3],
      venue: venue,
      grassroots: grassroots
    } do
      round = insert(:round, stage_id: grassroots.id, group_id: group.id)
      admin = insert(:admin)

      f1 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p2.id,
          venue_id: venue.id
        )

      f2 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p3.id,
          venue_id: venue.id
        )

      f3 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p2.id,
          participant_b_id: p3.id,
          venue_id: venue.id
        )

      Competitions.record_result(f1, admin, %{"winner_participation_id" => p1.id})
      Competitions.record_result(f2, admin, %{"winner_participation_id" => p1.id})
      Competitions.record_result(f3, admin, %{"winner_participation_id" => p2.id})

      config = Competitions.group_config(grassroots.id, "male")
      assert config.advancer_count == 2

      advancers = Competitions.top_advancers(group)
      assert length(advancers) == 2
      assert Enum.map(advancers, & &1.participant_id) == [p1.id, p2.id]
    end
  end

  describe "round_winners/1" do
    test "returns the winning participants of a Circuit knockout round" do
      circuit = stage("Circuit")
      bracket = Competitions.ensure_knockout_bracket(circuit.id, "male")

      p1 = insert(:stage_participation, stage_id: circuit.id, category: "male")
      p2 = insert(:stage_participation, stage_id: circuit.id, category: "male")
      p3 = insert(:stage_participation, stage_id: circuit.id, category: "male")
      p4 = insert(:stage_participation, stage_id: circuit.id, category: "male")

      {:ok, round} =
        Competitions.create_round(%{
          stage_id: circuit.id,
          knockout_bracket_id: bracket.id,
          name: "Round of 4"
        })

      venue = insert(:venue)
      admin = insert(:admin)

      f1 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p1.id,
          participant_b_id: p2.id,
          venue_id: venue.id
        )

      f2 =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: p3.id,
          participant_b_id: p4.id,
          venue_id: venue.id
        )

      Competitions.record_result(f1, admin, %{"winner_participation_id" => p1.id})
      Competitions.record_result(f2, admin, %{"winner_participation_id" => p4.id})

      winners = Competitions.round_winners(round)
      assert Enum.map(winners, & &1.id) |> Enum.sort() == Enum.sort([p1.id, p4.id])
    end
  end

  describe "record_points/3, correct_points/3, and points_total/1" do
    test "records points against a result and totals them live" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert {:ok, _entry} =
               Competitions.record_points(result, admin, %{
                 "participant_id" => fixture.participant_a_id,
                 "points" => 3
               })

      assert Competitions.points_total(fixture.participant_a_id) == 3

      assert {:ok, _entry2} =
               Competitions.record_points(result, admin, %{
                 "participant_id" => fixture.participant_a_id,
                 "points" => 2
               })

      assert Competitions.points_total(fixture.participant_a_id) == 5
    end

    test "a correction immediately reflects in points_total/1 with no double-counting" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      {:ok, entry} =
        Competitions.record_points(result, admin, %{
          "participant_id" => fixture.participant_a_id,
          "points" => 3
        })

      assert Competitions.points_total(fixture.participant_a_id) == 3

      assert {:ok, corrected} = Competitions.correct_points(entry, admin, %{"points" => 7})
      assert corrected.prior_value["points"] == 3

      assert Competitions.points_total(fixture.participant_a_id) == 7

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          entity_id: entry.id,
          action_type: "correct_points"
        )

      assert log.prior_value["points"] == 3
      assert log.new_value["points"] == 7
    end

    test "points_total/1 is 0 for a participant with no entries" do
      participant = insert(:stage_participation)
      assert Competitions.points_total(participant.id) == 0
    end

    test "record_points/3 broadcasts :points_updated on the \"standings\" topic" do
      Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      {:ok, entry} =
        Competitions.record_points(result, admin, %{
          "participant_id" => fixture.participant_a_id,
          "points" => 4
        })

      assert_receive {:points_updated, participant_id}
      assert participant_id == fixture.participant_a_id

      Competitions.correct_points(entry, admin, %{"points" => 6})
      assert_receive {:points_updated, ^participant_id}
    end
  end

  describe "standings_for_category/1" do
    test "ranks participants by Cuevo Points, zero-point participants sink to the bottom" do
      fixture = circuit_fixture("male")
      admin = insert(:admin)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      {:ok, _entry} =
        Competitions.record_points(result, admin, %{
          "participant_id" => fixture.participant_a_id,
          "points" => 5
        })

      standings = Competitions.standings_for_category("male")
      a = Enum.find(standings, &(&1.id == fixture.participant_a_id))
      b = Enum.find(standings, &(&1.id == fixture.participant_b_id))

      assert a.points == 5
      assert b.points == 0
      assert a.rank < b.rank
    end

    test "excludes Grassroots/Regional participants — standings only cover Circuit/Finals" do
      grassroots_p =
        insert(:stage_participation, stage_id: stage("Grassroots").id, category: "male")

      regional_p =
        insert(:stage_participation, stage_id: stage("Regional").id, category: "male")

      circuit_p = insert(:stage_participation, stage_id: stage("Circuit").id, category: "male")

      standings = Competitions.standings_for_category("male")
      ids = Enum.map(standings, & &1.id)

      refute grassroots_p.id in ids
      refute regional_p.id in ids
      assert circuit_p.id in ids
    end

    test "marks Circuit participants advancing when ranked within the Finals capacity for their category" do
      circuit = stage("Circuit")
      finals = stage("Finals")
      admin = insert(:admin)

      config = Competitions.capacity_config(finals.id, "male")
      {:ok, _} = Competitions.update_capacity_config(config, %{"capacity_limit" => 2})

      fixture = circuit_fixture("male")

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      p1 = insert(:stage_participation, stage_id: circuit.id, category: "male")
      p2 = insert(:stage_participation, stage_id: circuit.id, category: "male")
      p3 = insert(:stage_participation, stage_id: circuit.id, category: "male")

      Competitions.record_points(result, admin, %{"participant_id" => p1.id, "points" => 10})
      Competitions.record_points(result, admin, %{"participant_id" => p2.id, "points" => 5})
      Competitions.record_points(result, admin, %{"participant_id" => p3.id, "points" => 1})

      standings = Competitions.standings_for_category("male")
      by_id = Map.new(standings, &{&1.id, &1})

      assert by_id[p1.id].advancing
      assert by_id[p2.id].advancing
      refute by_id[p3.id].advancing
      refute by_id[fixture.participant_a_id].advancing
    end

    test "Finals participants are never marked advancing — there is no next stage" do
      finals = stage("Finals")
      admin = insert(:admin)
      bracket = Competitions.ensure_knockout_bracket(finals.id, "male")

      participant_a = insert(:stage_participation, stage_id: finals.id, category: "male")
      participant_b = insert(:stage_participation, stage_id: finals.id, category: "male")

      {:ok, round} =
        Competitions.create_round(%{
          stage_id: finals.id,
          knockout_bracket_id: bracket.id,
          name: "Final"
        })

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: participant_a.id,
          participant_b_id: participant_b.id
        )

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => participant_a.id
        })

      {:ok, _entry} =
        Competitions.record_points(result, admin, %{
          "participant_id" => participant_a.id,
          "points" => 20
        })

      standings = Competitions.standings_for_category("male")
      row = Enum.find(standings, &(&1.id == participant_a.id))

      refute row.advancing
    end
  end

  describe "migrate_regional_start_enrollments/0" do
    test "moves undrawn female and team Grassroots participations to Regional, leaving male alone" do
      grassroots = stage("Grassroots")
      regional = stage("Regional")
      region = build(:region)

      female_player = insert(:player, region_id: region.id, gender: "female")

      female_sp =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "female",
          player_id: female_player.id
        )

      captain = insert(:player, region_id: region.id)
      team = insert(:team, region_id: region.id, captain_id: captain.id)

      team_sp =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "team",
          team_id: team.id,
          player_id: nil
        )

      male_player = insert(:player, region_id: region.id, gender: "male")

      male_sp =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "male",
          player_id: male_player.id
        )

      assert %{moved: 2, skipped_drawn: 0} = Competitions.migrate_regional_start_enrollments()

      assert Repo.get!(Cuevolution.Competitions.StageParticipation, female_sp.id).stage_id ==
               regional.id

      assert Repo.get!(Cuevolution.Competitions.StageParticipation, team_sp.id).stage_id ==
               regional.id

      assert Repo.get!(Cuevolution.Competitions.StageParticipation, male_sp.id).stage_id ==
               grassroots.id
    end

    test "is idempotent and skips a participation already drawn into a group" do
      grassroots = stage("Grassroots")
      region = build(:region)
      venue = insert(:venue, region_id: region.id)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: grassroots.id,
          region_id: region.id,
          venue_id: venue.id,
          category: "female",
          name: "Drawn Pool"
        })

      female_player = insert(:player, region_id: region.id, gender: "female")

      female_sp =
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "female",
          player_id: female_player.id
        )

      {:ok, _} = Competitions.assign_to_group(female_sp, group)

      assert %{moved: 0, skipped_drawn: 1} = Competitions.migrate_regional_start_enrollments()

      assert Repo.get!(Cuevolution.Competitions.StageParticipation, female_sp.id).stage_id ==
               grassroots.id

      assert %{moved: 0, skipped_drawn: 1} = Competitions.migrate_regional_start_enrollments()
    end
  end

  describe "backfill_walkover_points/0" do
    defp legacy_walkover_fixture(fixture, score, winner_id) do
      admin = insert(:admin)

      {:ok, result} =
        %MatchResult{}
        |> MatchResult.create_changeset(%{
          fixture_id: fixture.id,
          winner_participation_id: winner_id,
          score: score,
          recorded_by_admin_id: admin.id
        })
        |> Repo.insert()

      Repo.update!(
        Ecto.Changeset.change(fixture,
          result_id: result.id,
          status: "walkover",
          walkover_kind: "single"
        )
      )

      result
    end

    test "adds points_a/points_b based on winner_participation_id, leaving frames untouched" do
      fixture = insert(:fixture) |> Repo.preload([:participant_a, :participant_b])

      result =
        legacy_walkover_fixture(
          fixture,
          %{"participant_a_frames" => 0, "participant_b_frames" => 5, "walkover" => true},
          fixture.participant_b_id
        )

      assert %{corrected: 1, skipped: []} = Competitions.backfill_walkover_points()

      updated = Repo.get!(MatchResult, result.id)
      assert updated.score["points_a"] == 0
      assert updated.score["points_b"] == 3
      assert updated.score["participant_a_frames"] == 0
      assert updated.score["participant_b_frames"] == 5
    end

    test "is idempotent — leaves a result alone once it already has points_a" do
      fixture = insert(:fixture) |> Repo.preload([:participant_a, :participant_b])

      result =
        legacy_walkover_fixture(
          fixture,
          %{
            "participant_a_frames" => 5,
            "participant_b_frames" => 0,
            "points_a" => 3,
            "points_b" => 0,
            "walkover" => true
          },
          fixture.participant_a_id
        )

      assert %{corrected: 0, skipped: []} = Competitions.backfill_walkover_points()
      assert Repo.get!(MatchResult, result.id).score["points_a"] == 3
    end

    test "skips a double walkover (no winner) instead of guessing a side" do
      fixture = insert(:fixture) |> Repo.preload([:participant_a, :participant_b])
      admin = insert(:admin)

      {:ok, result} =
        %MatchResult{}
        |> MatchResult.system_double_walkover_changeset(%{
          fixture_id: fixture.id,
          score: %{
            "participant_a_frames" => 0,
            "participant_b_frames" => 0,
            "walkover" => true,
            "walkover_kind" => "double"
          }
        })
        |> Ecto.Changeset.put_change(:recorded_by_admin_id, admin.id)
        |> Repo.insert()

      Repo.update!(
        Ecto.Changeset.change(fixture,
          result_id: result.id,
          status: "walkover",
          walkover_kind: "double"
        )
      )

      assert %{corrected: 0, skipped: [skipped_id]} = Competitions.backfill_walkover_points()
      assert skipped_id == result.id
    end
  end

  describe "revert_deadline_double_walkovers/0" do
    defp double_walkover_fixture do
      grassroots = stage("Grassroots")
      a = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      b = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      group = insert(:group, stage_id: grassroots.id, category: "male")
      round = insert(:round, stage_id: grassroots.id, group_id: group.id)

      fixture =
        insert(:fixture, round_id: round.id, participant_a_id: a.id, participant_b_id: b.id)

      {:ok, result} =
        %MatchResult{}
        |> MatchResult.system_double_walkover_changeset(%{
          fixture_id: fixture.id,
          score: %{
            "participant_a_frames" => 0,
            "participant_b_frames" => 0,
            "points_a" => 0,
            "points_b" => 0,
            "walkover" => true,
            "walkover_kind" => "double"
          }
        })
        |> Repo.insert()

      fixture =
        Repo.update!(
          Ecto.Changeset.change(fixture,
            result_id: result.id,
            status: "walkover",
            walkover_kind: "double"
          )
        )

      {fixture, result, a, b}
    end

    test "reverts a double walkover to scheduled, deleting the synthetic result" do
      {fixture, result, _a, _b} = double_walkover_fixture()

      assert %{reverted: 1, skipped_advanced: []} =
               Competitions.revert_deadline_double_walkovers()

      reverted = Repo.get!(Fixture, fixture.id)
      assert reverted.status == "scheduled"
      assert reverted.walkover_kind == nil
      assert reverted.result_id == nil
      assert Repo.get(MatchResult, result.id) == nil

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "revert_deadline_double_walkover",
          entity_id: fixture.id
        )

      assert log.actor_type == "system"
    end

    test "skips a fixture where a participant already advanced to the next stage" do
      {fixture, result, a, _b} = double_walkover_fixture()
      round_2 = stage("Grassroots Round 2")
      Repo.update!(Ecto.Changeset.change(a, stage_id: round_2.id))

      assert %{reverted: 0, skipped_advanced: [skipped_id]} =
               Competitions.revert_deadline_double_walkovers()

      assert skipped_id == fixture.id

      untouched = Repo.get!(Fixture, fixture.id)
      assert untouched.status == "walkover"
      assert untouched.walkover_kind == "double"
      assert Repo.get(MatchResult, result.id)
    end

    test "is idempotent — a second run finds nothing left to revert" do
      double_walkover_fixture()

      assert %{reverted: 1} = Competitions.revert_deadline_double_walkovers()

      assert %{reverted: 0, skipped_advanced: []} =
               Competitions.revert_deadline_double_walkovers()
    end

    test "leaves a real (single) walkover and a verified result alone" do
      single = insert(:fixture, status: "walkover", walkover_kind: "single")
      verified = insert(:fixture, status: "verified")

      assert %{reverted: 0, skipped_advanced: []} =
               Competitions.revert_deadline_double_walkovers()

      assert Repo.get!(Fixture, single.id).status == "walkover"
      assert Repo.get!(Fixture, verified.id).status == "verified"
    end

    test "leaves a double walkover alone once its result was manually corrected" do
      {fixture, result, _a, b} = double_walkover_fixture()

      admin = insert(:admin, role: "super_admin")

      {:ok, _corrected} =
        Competitions.correct_result(result, admin, %{
          "winner_participation_id" => b.id,
          "score" => %{"participant_a_frames" => 0, "participant_b_frames" => 5}
        })

      assert %{reverted: 0, skipped_advanced: []} =
               Competitions.revert_deadline_double_walkovers()

      untouched = Repo.get!(Fixture, fixture.id)
      assert untouched.status == "walkover"
      assert untouched.walkover_kind == "double"
      assert Repo.get!(MatchResult, result.id).winner_participation_id == b.id
    end
  end

  describe "list_pending_result_fixtures/4 and count_pending_result_fixtures/3 (search)" do
    test "matches by participant_a's player username" do
      player = insert(:player, username: "findable-rep", first_name: "Alpha", last_name: "One")
      pa = insert(:stage_participation, player_id: player.id)
      fixture = insert(:fixture, participant_a_id: pa.id)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{"winner_participation_id" => pa.id})

      other = insert(:fixture)

      {:ok, _other_result} =
        Competitions.record_result(other, admin, %{
          "winner_participation_id" => other.participant_a_id
        })

      assert Competitions.list_pending_result_fixtures(nil, nil, 1, "findable")
             |> Enum.map(& &1.id) == [fixture.id]

      assert Competitions.count_pending_result_fixtures(nil, nil, "findable") == 1
    end

    test "matches by participant_b's player first or last name, case-insensitively" do
      player = insert(:player, first_name: "Zanele", last_name: "Mbatha")
      pb = insert(:stage_participation, player_id: player.id)
      fixture = insert(:fixture, participant_b_id: pb.id)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{"winner_participation_id" => pb.id})

      assert Competitions.list_pending_result_fixtures(nil, nil, 1, "zanele")
             |> Enum.map(& &1.id) == [fixture.id]

      assert Competitions.list_pending_result_fixtures(nil, nil, 1, "MBATHA")
             |> Enum.map(& &1.id) == [fixture.id]
    end

    test "a search term matching nobody returns no results, not an error" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert Competitions.list_pending_result_fixtures(nil, nil, 1, "no-such-player") == []
      assert Competitions.count_pending_result_fixtures(nil, nil, "no-such-player") == 0
    end

    test "search also narrows the approved results list and count" do
      player = insert(:player, username: "verified-rep")
      pa = insert(:stage_participation, player_id: player.id)
      fixture = insert(:fixture, participant_a_id: pa.id)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{"winner_participation_id" => pa.id})

      {:ok, _verified} = Competitions.verify_result(Repo.reload(fixture), admin)

      assert Competitions.list_approved_result_fixtures(nil, nil, 1, "verified-rep")
             |> Enum.map(& &1.id) == [fixture.id]

      assert Competitions.count_approved_result_fixtures(nil, nil, "verified-rep") == 1
    end

    test "a blank search term is the same as no search" do
      fixture = insert(:fixture)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id
        })

      assert Competitions.count_pending_result_fixtures(nil, nil, "") ==
               Competitions.count_pending_result_fixtures(nil, nil)
    end
  end

  describe "move_back_to_previous_stage/2" do
    defp placed_in(participation, stage_name, opts \\ []) do
      stage = stage(stage_name)
      group = insert(:group, stage_id: stage.id, category: participation.category)
      round = insert(:round, stage_id: stage.id, group_id: group.id)

      membership =
        insert(:group_membership, group_id: group.id, stage_participation_id: participation.id)

      opponent =
        insert(:stage_participation, stage_id: stage.id, category: participation.category)

      fixture =
        insert(:fixture,
          round_id: round.id,
          participant_a_id: participation.id,
          participant_b_id: opponent.id,
          status: Keyword.get(opts, :status, "scheduled")
        )

      %{group: group, membership: membership, fixture: fixture}
    end

    test "moves back one stage, cleaning up only the stage it leaves" do
      admin = insert(:admin, role: "tournament_director")
      round_2 = stage("Grassroots Round 2")
      participation = insert(:stage_participation, stage_id: round_2.id, category: "male")

      # Their Grassroots history is intact and must survive the move.
      participation = %{participation | stage_id: stage("Grassroots").id}
      kept = placed_in(participation, "Grassroots", status: "verified")
      participation = %{participation | stage_id: round_2.id}

      Repo.update_all(from(sp in StageParticipation, where: sp.id == ^participation.id),
        set: [stage_id: round_2.id]
      )

      removed = placed_in(participation, "Grassroots Round 2")

      assert {:ok, updated} = Competitions.move_back_to_previous_stage(participation, admin)
      assert updated.stage_id == stage("Grassroots").id

      refute Repo.get(Fixture, removed.fixture.id)
      refute Repo.get(GroupMembership, removed.membership.id)
      assert Repo.get(Fixture, kept.fixture.id)
      assert Repo.get(GroupMembership, kept.membership.id)
    end

    test "records the move in the audit log with what was removed" do
      admin = insert(:admin, role: "super_admin")

      participation =
        insert(:stage_participation, stage_id: stage("Regional").id, category: "male")

      placed_in(participation, "Regional")

      assert {:ok, updated} = Competitions.move_back_to_previous_stage(participation, admin)

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          action_type: "move_back_to_stage",
          entity_id: updated.id
        )

      assert log.prior_value == %{"stage_id" => stage("Regional").id}

      assert %{"stage_id" => _, "removed_fixtures" => 1, "removed_group_memberships" => 1} =
               log.new_value
    end

    test "refuses, changing nothing, when they have a played fixture in the stage" do
      admin = insert(:admin, role: "tournament_director")

      participation =
        insert(:stage_participation, stage_id: stage("Regional").id, category: "male")

      played = placed_in(participation, "Regional", status: "verified")

      assert {:error, :has_recorded_results} =
               Competitions.move_back_to_previous_stage(participation, admin)

      assert Repo.get!(StageParticipation, participation.id).stage_id == stage("Regional").id
      assert Repo.get(Fixture, played.fixture.id)
      assert Repo.get(GroupMembership, played.membership.id)
    end

    test "refuses when a scheduled fixture already has a result attached" do
      admin = insert(:admin, role: "tournament_director")

      participation =
        insert(:stage_participation, stage_id: stage("Regional").id, category: "male")

      %{fixture: fixture} = placed_in(participation, "Regional")
      result = insert(:match_result)
      Repo.update_all(from(f in Fixture, where: f.id == ^fixture.id), set: [result_id: result.id])

      assert {:error, :has_recorded_results} =
               Competitions.move_back_to_previous_stage(participation, admin)
    end

    test "releases the slot in a capped stage" do
      admin = insert(:admin, role: "super_admin")
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "female")

      Repo.update_all(from(c in StageCapacityConfig, where: c.id == ^config.id),
        set: [current_count: 3]
      )

      participation = insert(:stage_participation, stage_id: finals.id, category: "female")

      assert {:ok, updated} = Competitions.move_back_to_previous_stage(participation, admin)

      assert updated.stage_id == stage("Circuit").id
      assert Repo.get!(StageCapacityConfig, config.id).current_count == 2
    end

    test "has no earlier stage for the first stage, or for female/team entering at Regional" do
      admin = insert(:admin, role: "super_admin")
      first = insert(:stage_participation, stage_id: stage("Grassroots").id, category: "male")
      female = insert(:stage_participation, stage_id: stage("Regional").id, category: "female")

      team =
        insert(:stage_participation,
          stage_id: stage("Regional").id,
          category: "team",
          player_id: nil,
          team_id: insert(:team).id
        )

      assert {:error, :no_previous_stage} = Competitions.move_back_to_previous_stage(first, admin)

      assert {:error, :no_previous_stage} =
               Competitions.move_back_to_previous_stage(female, admin)

      assert {:error, :no_previous_stage} = Competitions.move_back_to_previous_stage(team, admin)
    end

    test "is restricted to roles that can advance participants" do
      admin = insert(:admin, role: "regional_coordinator", region_id: build(:region).id)

      participation =
        insert(:stage_participation, stage_id: stage("Regional").id, category: "male")

      assert {:error, :unauthorized} =
               Competitions.move_back_to_previous_stage(participation, admin)

      assert Repo.get!(StageParticipation, participation.id).stage_id == stage("Regional").id
    end
  end
end
