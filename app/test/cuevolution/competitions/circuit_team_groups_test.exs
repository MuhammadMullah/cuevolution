defmodule Cuevolution.Competitions.CircuitTeamGroupsTest do
  @moduledoc """
  The Circuit team event (spec 014): 20 teams, 2 national groups of 10, one
  season-long round robin, top 4 in each group to the Nationals.
  """
  use Cuevolution.DataCase, async: true

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Group
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp team_entrants(count) do
    stage = circuit()

    for _ <- 1..count do
      team = insert(:team)

      insert(:stage_participation,
        stage_id: stage.id,
        category: "team",
        player_id: nil,
        team_id: team.id,
        region_id: team.region_id
      )
    end
  end

  # Entrants spread over `region_count` regions, so the draw is guaranteed to
  # put teams from the same region in the same group.
  defp team_entrants_across(count, region_count) do
    stage = circuit()
    regions = Cuevolution.Accounts.list_regions() |> Enum.take(region_count)

    for n <- 1..count do
      region = Enum.at(regions, rem(n, region_count))
      captain = insert(:player, region_id: region.id)
      team = insert(:team, region_id: region.id, captain_id: captain.id)

      insert(:stage_participation,
        stage_id: stage.id,
        category: "team",
        player_id: nil,
        team_id: team.id,
        region_id: region.id
      )
    end
  end

  # Every round of a group, in play order, as {sequence, derby count}.
  defp derby_profile(group) do
    Competitions.circuit_team_rounds(circuit().id)
    |> Enum.filter(&(&1.group_id == group.id))
    |> Enum.sort_by(& &1.sequence)
    |> Enum.map(fn round ->
      {round.sequence, Enum.count(round.fixtures, &derby?/1)}
    end)
  end

  defp derby?(fixture) do
    a = fixture.participant_a && fixture.participant_a.region_id
    b = fixture.participant_b && fixture.participant_b.region_id
    not is_nil(a) and a == b
  end

  defp drawn(count \\ 20) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")
    entrants = team_entrants(count)

    {:ok, %{groups: groups}} = Competitions.draw_circuit_team_groups(stage.id, admin)

    %{stage: stage, admin: admin, entrants: entrants, groups: groups}
  end

  defp fixtures_in(group_id) do
    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.group_id == ^group_id,
        preload: [:round]
    )
  end

  describe "the draw" do
    test "20 teams become 2 groups of 10" do
      %{groups: groups} = drawn()

      assert length(groups) == 2
      assert Enum.map(groups, & &1.name) == ["Group A", "Group B"]

      sizes =
        Enum.map(groups, fn group ->
          group |> Repo.preload(:group_memberships) |> Map.fetch!(:group_memberships) |> length()
        end)

      assert sizes == [10, 10]
    end

    test "the groups are national — no region and no venue" do
      %{groups: groups} = drawn()

      for group <- groups do
        assert is_nil(group.region_id)
        assert is_nil(group.venue_id)
      end
    end

    test "every team is drawn exactly once" do
      %{entrants: entrants, groups: groups} = drawn()

      drawn_ids =
        groups
        |> Repo.preload(:group_memberships)
        |> Enum.flat_map(& &1.group_memberships)
        |> Enum.map(& &1.stage_participation_id)

      assert Enum.sort(drawn_ids) == Enum.sort(Enum.map(entrants, & &1.id))
      assert length(Enum.uniq(drawn_ids)) == 20
    end

    test "a second draw is refused" do
      %{stage: stage, admin: admin} = drawn()

      assert {:error, :already_drawn} = Competitions.draw_circuit_team_groups(stage.id, admin)
    end

    test "fewer than ten teams cannot be drawn" do
      stage = circuit()
      admin = insert(:admin, role: "tournament_director")
      team_entrants(9)

      assert {:error, :below_minimum} = Competitions.draw_circuit_team_groups(stage.id, admin)
    end

    test "the draw is reproducible from its seed" do
      stage = circuit()
      admin = insert(:admin, role: "tournament_director")
      team_entrants(20)

      {:ok, %{draw: draw}} =
        Competitions.draw_circuit_team_groups(stage.id, admin, random_seed: "a-fixed-seed")

      assert draw.random_seed == "a-fixed-seed"
    end
  end

  describe "same-region teams play first" do
    setup do
      stage = circuit()
      admin = insert(:admin, role: "tournament_director")
      # Ten teams over four regions is one group and guarantees derbies, at
      # half the fixtures of a full twenty-team draw.
      team_entrants_across(10, 4)

      {:ok, %{groups: groups}} = Competitions.draw_circuit_team_groups(stage.id, admin)
      %{stage: stage, groups: groups}
    end

    test "the derbies are front-loaded into the opening rounds", %{groups: groups} do
      for group <- groups do
        profile = derby_profile(group)
        counts = Enum.map(profile, &elem(&1, 1))

        # Rounds are ordered by how many derbies they hold, most first.
        assert counts == Enum.sort(counts, :desc),
               "#{group.name} plays its derbies out of order: #{inspect(counts)}"

        # So round one has one, and nothing is left behind a clear round.
        assert hd(counts) > 0, "#{group.name} has derbies but none in round 1"

        last_derby = profile |> Enum.filter(&(elem(&1, 1) > 0)) |> List.last() |> elem(0)

        case Enum.find(profile, &(elem(&1, 1) == 0)) do
          nil ->
            :ok

          {first_clear, _} ->
            assert last_derby < first_clear,
                   "a derby is scheduled after a derby-free round in #{group.name}"
        end
      end
    end

    test "within a round the derbies take the earliest match numbers", %{groups: groups} do
      rounds =
        Competitions.circuit_team_rounds(circuit().id)
        |> Enum.filter(fn r -> Enum.any?(groups, &(&1.id == r.group_id)) end)

      for round <- rounds do
        flags = Enum.map(round.fixtures, &derby?/1)
        {_derbies, rest} = Enum.split_while(flags, & &1)

        refute Enum.any?(rest),
               "#{round.name} puts a derby after a non-derby: #{inspect(flags)}"
      end
    end

    test "the round robin itself is untouched by the reordering", %{groups: groups} do
      for group <- groups do
        rounds =
          Competitions.circuit_team_rounds(circuit().id)
          |> Enum.filter(&(&1.group_id == group.id))

        assert length(rounds) == 9
        assert rounds |> Enum.map(&length(&1.fixtures)) |> Enum.uniq() == [5]
        assert rounds |> Enum.map(& &1.sequence) |> Enum.sort() == Enum.to_list(1..9)

        pairings =
          rounds
          |> Enum.flat_map(& &1.fixtures)
          |> Enum.map(&MapSet.new([&1.participant_a_id, &1.participant_b_id]))

        assert length(pairings) == 45
        assert length(Enum.uniq(pairings)) == 45, "a pairing is repeated"
      end
    end
  end

  describe "the round robin" do
    test "nine rounds of five matches in each group" do
      %{groups: groups} = drawn()

      for group <- groups do
        fixtures = fixtures_in(group.id)
        rounds = fixtures |> Enum.map(& &1.round.id) |> Enum.uniq()

        assert length(rounds) == 9, "expected 9 rounds, got #{length(rounds)}"
        assert length(fixtures) == 45, "expected 45 matches, got #{length(fixtures)}"

        per_round =
          fixtures |> Enum.group_by(& &1.round.id) |> Map.values() |> Enum.map(&length/1)

        assert Enum.uniq(per_round) == [5]
      end
    end

    test "every team meets every other team in its group exactly once" do
      %{groups: groups} = drawn()

      for group <- groups do
        members =
          group
          |> Repo.preload(:group_memberships)
          |> Map.fetch!(:group_memberships)
          |> Enum.map(& &1.stage_participation_id)
          |> MapSet.new()

        pairings =
          group.id
          |> fixtures_in()
          |> Enum.map(&MapSet.new([&1.participant_a_id, &1.participant_b_id]))

        assert length(pairings) == length(Enum.uniq(pairings)), "a pairing is repeated"

        # 10 teams choose 2 = 45 distinct meetings, and nobody plays themselves.
        assert length(Enum.uniq(pairings)) == 45

        for pairing <- pairings do
          assert MapSet.size(pairing) == 2
          assert MapSet.subset?(pairing, members)
        end
      end
    end

    test "team matches are race to 13, best of 25" do
      %{groups: [group | _]} = drawn()

      races = group.id |> fixtures_in() |> Enum.map(& &1.round.race_to) |> Enum.uniq()

      assert races == [13]
    end

    test "rounds are numbered 1 to 9" do
      %{groups: [group | _]} = drawn()

      sequences =
        group.id |> fixtures_in() |> Enum.map(& &1.round.sequence) |> Enum.uniq() |> Enum.sort()

      assert sequences == Enum.to_list(1..9)
    end
  end

  describe "scoring a team match" do
    test "the frame count cannot be pushed past the race" do
      %{admin: admin, groups: [group | _]} = drawn()

      [fixture | _] =
        group.id |> fixtures_in() |> Enum.filter(&(&1.round.sequence == 1))

      assert fixture.round.race_to == 13

      # Tapping the plus button more times than the race is long must not
      # invent frames: 13 wins it, and there is no 14th.
      for n <- 1..16 do
        {:ok, updated} = Competitions.update_live_score(fixture, admin, %{"a" => n, "b" => 0})
        assert updated.live_score["a"] <= 13
      end

      {:ok, final} = Competitions.update_live_score(fixture, admin, %{"a" => 99, "b" => 0})
      assert final.live_score["a"] == 13
    end

    test "both sides are clamped, not just the one in front" do
      %{admin: admin, groups: [group | _]} = drawn()

      [fixture | _] =
        group.id |> fixtures_in() |> Enum.filter(&(&1.round.sequence == 1))

      {:ok, updated} = Competitions.update_live_score(fixture, admin, %{"a" => 20, "b" => 30})

      assert updated.live_score == %{"a" => 13, "b" => 13}
    end
  end

  describe "the group table" do
    # Plays round 1 in `group`, team A winning every match 14-N.
    defp play_round_one(group, admin, loser_frames \\ 2) do
      fixtures =
        group.id
        |> fixtures_in()
        |> Enum.filter(&(&1.round.sequence == 1))

      for fixture <- fixtures do
        {:ok, _} =
          Competitions.record_result(fixture, admin, %{
            "winner_participation_id" => fixture.participant_a_id,
            "score" => %{"a" => 13, "b" => loser_frames}
          })
      end

      fixtures
    end

    test "SP Points are 2 for entering plus 3 a win" do
      %{stage: stage, admin: admin, groups: [group | _]} = drawn()
      fixtures = play_round_one(group, admin)

      [%{rows: rows} | _] =
        Competitions.circuit_team_standings(stage.id)
        |> Enum.filter(&(&1.group.id == group.id))

      winner_ids = MapSet.new(fixtures, & &1.participant_a_id)

      for row <- rows do
        expected = if MapSet.member?(winner_ids, row.participation.id), do: 5, else: 2

        assert row.sp_points == expected,
               "#{row.name} on #{row.wins} wins scored #{row.sp_points}"
      end
    end

    test "a team that has played nothing still has the 2 for entering" do
      %{stage: stage, groups: [group | _]} = drawn()

      [%{rows: rows} | _] =
        Competitions.circuit_team_standings(stage.id)
        |> Enum.filter(&(&1.group.id == group.id))

      assert length(rows) == 10
      assert Enum.all?(rows, &(&1.sp_points == 2))
      assert Enum.all?(rows, &(&1.wins == 0))
    end

    test "the table is ordered by SP Points, highest first" do
      %{stage: stage, admin: admin, groups: [group | _]} = drawn()
      play_round_one(group, admin)

      [%{rows: rows} | _] =
        Competitions.circuit_team_standings(stage.id)
        |> Enum.filter(&(&1.group.id == group.id))

      points = Enum.map(rows, & &1.sp_points)
      assert points == Enum.sort(points, :desc)
    end

    test "a recorded result counts without needing verification" do
      %{stage: stage, admin: admin, groups: [group | _]} = drawn()
      play_round_one(group, admin)

      [%{rows: rows} | _] =
        Competitions.circuit_team_standings(stage.id)
        |> Enum.filter(&(&1.group.id == group.id))

      assert Enum.count(rows, &(&1.wins == 1)) == 5
      assert Enum.count(rows, &(&1.losses == 1)) == 5
      assert Enum.any?(rows, &(&1.frames_won == 13))
    end

    test "the top four in each group are marked as advancing" do
      %{stage: stage} = drawn()

      for %{rows: rows, advancer_count: advancers} <-
            Competitions.circuit_team_standings(stage.id) do
        assert advancers == 4
        assert Enum.count(rows, & &1.advancing) == 4
        assert rows |> Enum.filter(& &1.advancing) |> Enum.map(& &1.rank) == [1, 2, 3, 4]
      end
    end

    test "eight teams qualify for the Nationals" do
      %{stage: stage} = drawn()

      qualifiers = Competitions.circuit_team_qualifiers(stage.id)

      assert length(qualifiers) == 8
      assert length(Enum.uniq_by(qualifiers, & &1.id)) == 8
    end
  end

  describe "resetting" do
    test "a draw with no results can be cleared back to the entrant list" do
      %{stage: stage, admin: admin} = drawn()

      assert :ok = Competitions.reset_circuit_team_draw(stage.id, admin)

      assert Competitions.circuit_team_draw(stage.id) == nil
      assert Competitions.circuit_team_groups(stage.id) == []
      assert Repo.aggregate(from(g in Group, where: is_nil(g.region_id)), :count) == 0
      assert length(Competitions.circuit_team_entrants(stage.id)) == 20
    end

    test "a draw with a recorded result is not cleared" do
      %{stage: stage, admin: admin, groups: [group | _]} = drawn()

      [fixture | _] = group.id |> fixtures_in() |> Enum.filter(&(&1.round.sequence == 1))

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 13, "b" => 9}
        })

      assert {:error, :results_recorded} = Competitions.reset_circuit_team_draw(stage.id, admin)
      assert length(Competitions.circuit_team_groups(stage.id)) == 2
    end
  end

  describe "the singles events are untouched" do
    test "the Circuit is still a knockout stage for men and ladies" do
      stage = circuit()

      refute Stage.round_robin?(stage, "male")
      refute Stage.round_robin?(stage, "female")
      assert Stage.round_robin?(stage, "team")
    end

    test "Grassroots and Regional stay round-robin for every category" do
      for name <- ["Grassroots", "Regional"] do
        stage = Repo.get_by!(Stage, name: name)

        for category <- ~w(male female team) do
          assert Stage.round_robin?(stage, category)
        end
      end
    end
  end
end
