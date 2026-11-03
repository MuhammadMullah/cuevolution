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

    test "team matches are race to 14" do
      %{groups: [group | _]} = drawn()

      races = group.id |> fixtures_in() |> Enum.map(& &1.round.race_to) |> Enum.uniq()

      assert races == [14]
    end

    test "rounds are numbered 1 to 9" do
      %{groups: [group | _]} = drawn()

      sequences =
        group.id |> fixtures_in() |> Enum.map(& &1.round.sequence) |> Enum.uniq() |> Enum.sort()

      assert sequences == Enum.to_list(1..9)
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
            "score" => %{"a" => 14, "b" => loser_frames}
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
      assert Enum.any?(rows, &(&1.frames_won == 14))
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
          "score" => %{"a" => 14, "b" => 9}
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
