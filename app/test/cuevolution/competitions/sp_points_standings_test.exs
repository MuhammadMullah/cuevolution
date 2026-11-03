defmodule Cuevolution.Competitions.SpPointsStandingsTest do
  @moduledoc false
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  # Plays an entire bracket through, always giving the win to whoever sits in
  # slot A, so the finishing order is deterministic.
  defp play_out(bracket, admin) do
    rounds =
      Repo.all(
        from r in Round,
          where: r.knockout_bracket_id == ^bracket.id,
          order_by: [asc: r.sequence],
          select: r.id
      )

    for round_id <- rounds do
      fixtures =
        Repo.all(
          from f in Fixture,
            where: f.round_id == ^round_id and is_nil(f.result_id) and f.bye == false,
            order_by: [asc: f.slot]
        )

      for fixture <- fixtures, fixture.participant_a_id && fixture.participant_b_id do
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 1}
        })
      end
    end
  end

  defp standings(count \\ 8) do
    stage = circuit()
    admin = insert(:admin, role: "super_admin")

    players =
      for _ <- 1..count, do: insert(:stage_participation, stage_id: stage.id, category: "male")

    {:ok, %{bracket: bracket}} =
      Competitions.generate_circuit_bracket(stage.id, "male", players)

    play_out(bracket, admin)
    {Competitions.sp_points_standings(bracket.id), players}
  end

  describe "sp_points_standings/1" do
    test "every entrant appears, scored from what they actually did" do
      {table, players} = standings()

      assert length(table) == length(players)

      assert Enum.map(table, & &1.participation.id) |> Enum.sort() ==
               Enum.map(players, & &1.id) |> Enum.sort()
    end

    test "the champion tops it with the champion bonus" do
      {table, _} = standings()
      champion = hd(table)

      assert champion.finish == :champion
      # An 8-player bracket puts only 4 into the knockout, so that phase is
      # the semifinals and the final: W1, W2, SF, F — 4 wins unbeaten.
      assert champion.wins == 4
      assert champion.points == 2 + 4 * 3 + 20
      assert champion.points == 34
    end

    test "runner-up and semi-finalists get their bonuses, quarter-finalists do not" do
      {table, _} = standings()
      by_finish = Enum.group_by(table, & &1.finish)

      assert length(by_finish[:champion]) == 1
      assert length(by_finish[:runner_up]) == 1
      assert length(Map.get(by_finish, :semi_finalist, [])) == 2

      [runner_up] = by_finish[:runner_up]
      assert runner_up.points == 2 + runner_up.wins * 3 + 10

      for sf <- by_finish[:semi_finalist] do
        assert sf.points == 2 + sf.wins * 3 + 5
      end

      for other <- Map.get(by_finish, :none, []) do
        assert other.points == 2 + other.wins * 3
      end
    end

    test "it is ordered strongest first" do
      {table, _} = standings()
      points = Enum.map(table, & &1.points)

      assert points == Enum.sort(points, :desc)
    end

    test "a player knocked out immediately still scores the showing-up 2" do
      {table, _} = standings()
      lowest = List.last(table)

      assert lowest.wins == 0
      assert lowest.points == 2
    end

    test "a bye counts as a win even though no result is recorded" do
      stage = circuit()
      admin = insert(:admin, role: "super_admin")

      players =
        for _ <- 1..6, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players, byes: :random, rng: 3)

      bye =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and f.bye == true,
            limit: 1
        )

      had_bye = bye.participant_a_id || bye.participant_b_id

      play_out(bracket, admin)

      entry =
        Enum.find(Competitions.sp_points_standings(bracket.id), &(&1.participation.id == had_bye))

      assert entry, "the player who received a bye should still appear in the standings"
      assert entry.wins >= 1, "a bye should count as a win"
    end

    test "an unplayed bracket scores everyone on attendance alone" do
      stage = circuit()

      players =
        for _ <- 1..8, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players)

      table = Competitions.sp_points_standings(bracket.id)

      assert length(table) == 8
      assert Enum.all?(table, &(&1.points == 2 and &1.wins == 0 and &1.finish == :none))
    end
  end
end
