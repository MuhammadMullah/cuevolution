defmodule Cuevolution.CompetitionsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig

  defp stage(name), do: Repo.get_by!(Stage, name: name)

  describe "list_stages/0" do
    test "returns all 4 seeded stages in pipeline order" do
      assert Enum.map(Competitions.list_stages(), & &1.name) == [
               "Grassroots",
               "Regional",
               "Circuit",
               "Finals"
             ]
    end
  end

  describe "next_stage/1" do
    test "returns the following stage" do
      assert Competitions.next_stage(stage("Grassroots")).name == "Regional"
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

  describe "advance_to_stage/2" do
    test "never rejects for an open destination stage" do
      participation = insert(:stage_participation, stage_id: stage("Grassroots").id)

      assert {:ok, updated} =
               Competitions.advance_to_stage(participation, stage("Regional"))

      assert updated.stage_id == stage("Regional").id
    end

    test "accepts while under capacity and increments current_count" do
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "female")

      participation =
        insert(:stage_participation, stage_id: stage("Circuit").id, category: "female")

      assert {:ok, _updated} = Competitions.advance_to_stage(participation, finals)

      assert Repo.get!(StageCapacityConfig, config.id).current_count == config.current_count + 1
    end

    test "rejects with :capacity_exceeded once the limit is reached" do
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

      assert {:error, :capacity_exceeded} = Competitions.advance_to_stage(participation, finals)
    end

    test "does not increment current_count on a lost/rejected advance" do
      finals = stage("Finals")
      config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "male")

      Repo.update_all(
        from(c in StageCapacityConfig, where: c.id == ^config.id),
        set: [current_count: config.capacity_limit]
      )

      participation =
        insert(:stage_participation, stage_id: stage("Circuit").id, category: "male")

      assert {:error, :capacity_exceeded} = Competitions.advance_to_stage(participation, finals)

      assert Repo.get!(StageCapacityConfig, config.id).current_count == config.capacity_limit
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
      venue: venue,
      grassroots: grassroots
    } do
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
          stage_id: grassroots.id,
          region_id: region.id,
          venue_id: venue.id,
          category: "team",
          name: "Team Pool A"
        })

      Competitions.assign_to_group(team_pa, team_group)
      Competitions.assign_to_group(team_pb, team_group)

      {:ok, team_round} =
        Competitions.create_round(%{
          stage_id: grassroots.id,
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
      fixture = insert(:fixture)
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

      fixture = Repo.preload(fixture, [:participant_a, :participant_b])
      category = fixture.participant_a.category

      standings = Competitions.standings_for_category(category)
      a = Enum.find(standings, &(&1.id == fixture.participant_a_id))
      b = Enum.find(standings, &(&1.id == fixture.participant_b_id))

      assert a.points == 5
      assert b.points == 0
      assert a.rank < b.rank
    end
  end
end
