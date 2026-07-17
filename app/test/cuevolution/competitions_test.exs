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
    test "Grassroots group creation does not create a knockout bracket" do
      region = build(:region)

      assert {:ok, group} =
               Competitions.create_group(%{
                 stage_id: stage("Grassroots").id,
                 region_id: region.id,
                 name: "Pool A"
               })

      refute Repo.get_by(Competitions.KnockoutBracket, group_id: group.id)
    end

    test "Regional group creation auto-creates an empty knockout bracket" do
      region = build(:region)

      assert {:ok, group} =
               Competitions.create_group(%{
                 stage_id: stage("Regional").id,
                 region_id: region.id,
                 name: "Pool A"
               })

      assert Repo.get_by(Competitions.KnockoutBracket, group_id: group.id)
    end

    test "assigns a participation to a group" do
      region = build(:region)

      {:ok, group} =
        Competitions.create_group(%{
          stage_id: stage("Grassroots").id,
          region_id: region.id,
          name: "Pool A"
        })

      participation =
        insert(:stage_participation, stage_id: stage("Grassroots").id, region_id: region.id)

      assert {:ok, _membership} = Competitions.assign_to_group(participation, group)

      assert [%{stage_participation_id: id}] =
               Competitions.list_groups(stage("Grassroots").id, region.id)
               |> List.first()
               |> Map.fetch!(:group_memberships)

      assert id == participation.id
    end
  end

  describe "list_unassigned_participations/2" do
    test "excludes participations already in a group for that stage" do
      region = build(:region)
      stage_id = stage("Grassroots").id

      {:ok, group} =
        Competitions.create_group(%{stage_id: stage_id, region_id: region.id, name: "Pool A"})

      grouped = insert(:stage_participation, stage_id: stage_id, region_id: region.id)
      ungrouped = insert(:stage_participation, stage_id: stage_id, region_id: region.id)
      Competitions.assign_to_group(grouped, group)

      results = Competitions.list_unassigned_participations(stage_id, region.id)

      assert Enum.map(results, & &1.id) == [ungrouped.id]
    end
  end

  describe "create_round/1 and list_rounds_for_stage/1" do
    test "creates and lists rounds for a stage" do
      grassroots = stage("Grassroots")
      {:ok, round} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

      assert Competitions.list_rounds_for_stage(grassroots.id) |> Enum.map(& &1.id) == [round.id]
    end
  end

  describe "Fixture.changeset/3 same-category/same-stage cross-check (FR-006)" do
    test "rejects participants of different categories even if otherwise valid" do
      grassroots = stage("Grassroots")
      pa = insert(:stage_participation, stage_id: grassroots.id, category: "male")
      pb = insert(:stage_participation, stage_id: grassroots.id, category: "female")
      venue = insert(:venue)
      {:ok, round} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

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
      {:ok, round} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

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
      {:ok, round} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 1"})

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
      grassroots: grassroots
    } do
      assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [row])

      {:ok, round_2} = Competitions.create_round(%{stage_id: grassroots.id, name: "Round 2"})
      assert [{:ok, _fixture_2}] = Competitions.enter_fixtures(round_2, [row])
    end

    test "batch entry commits valid rows and reports the specific error for a bad one", %{
      round: round,
      row: row
    } do
      bad_row = Map.put(row, "b_id", Ecto.UUID.generate())

      assert [ok_result, error_result] = Competitions.enter_fixtures(round, [row, bad_row])
      assert {:ok, _fixture} = ok_result
      assert {:error, {:participant_b, :participant_not_in_stage}} = error_result
    end

    test "reports :invalid_datetime for a blank date/time", %{round: round, row: row} do
      bad_row = %{row | "date" => "", "time" => ""}
      assert [{:error, :invalid_datetime}] = Competitions.enter_fixtures(round, [bad_row])
    end

    test "Team-category fixtures dispatch to every roster member of both teams", %{
      region: region,
      venue: venue,
      round: round
    } do
      captain_a = insert(:player, region_id: region.id)
      {:ok, team_a} = Cuevolution.Teams.create_team(captain_a, %{"name" => "Team A"})
      member_a = insert(:player, region_id: region.id)
      {:ok, _} = Cuevolution.Teams.add_player_to_roster(team_a, member_a)

      captain_b = insert(:player, region_id: region.id)
      {:ok, team_b} = Cuevolution.Teams.create_team(captain_b, %{"name" => "Team B"})

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

      assert [{:ok, _fixture}] = Competitions.enter_fixtures(round, [team_row])

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
      fixture = insert(:fixture, result_id: Ecto.UUID.generate())

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
end
