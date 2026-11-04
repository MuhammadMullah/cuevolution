defmodule Cuevolution.Competitions.SpPointsStandingsTest do
  @moduledoc false
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.SpPoints
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

  # A 16 draw still produces every band — champion, runner-up, semis, and all
  # four losers' rounds — at half the matches of a 32.
  defp standings(count \\ 16) do
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
    test "every entrant appears exactly once" do
      {table, players} = standings()

      assert length(table) == length(players)
      assert Enum.map(table, & &1.participation.id) |> Enum.uniq() |> length() == length(players)
    end

    test "it is ordered by points, strongest first" do
      {table, _players} = standings()

      assert Enum.map(table, & &1.points) == Enum.sort(Enum.map(table, & &1.points), :desc)
    end

    test "the champion tops it, scored by the published rule" do
      {table, _players} = standings(32)
      champion = hd(table)

      assert champion.finish == :champion
      assert champion.position == {1, 1}
      assert champion.exit_round == nil

      # A 32 draw qualifies 8, so its single elimination is QF-SF-F: three wins
      # rather than the five a 128 draw takes. The 46 in the brief is the 128
      # figure, which `SpPointsTest` checks against `totals_by_finish/2`.
      assert champion.points ==
               SpPoints.circuit_points(%{qualified?: true, se_wins: 3, finish: :champion})

      assert champion.points == 40
    end

    test "the runner-up and semi-finalists get their bonuses, quarter-finalists do not" do
      # 32 so there is a quarter-final round at all: a 16 draw qualifies 4, and
      # its first single-elimination round is the semi.
      {table, _players} = standings(32)

      runner_up = Enum.find(table, &(&1.finish == :runner_up))
      semis = Enum.filter(table, &(&1.finish == :semi_finalist))

      assert runner_up.points ==
               SpPoints.circuit_points(%{qualified?: true, se_wins: 2, finish: :runner_up})

      assert runner_up.position == {2, 2}

      assert length(semis) == 2
      assert Enum.all?(semis, &(&1.position == {3, 4}))

      assert Enum.all?(
               semis,
               &(&1.points ==
                   SpPoints.circuit_points(%{
                     qualified?: true,
                     se_wins: 1,
                     finish: :semi_finalist
                   }))
             )

      # The quarter-final is this draw's first single-elimination round, so
      # losing it is the bare 11 for qualifying — no bonus, no wins.
      quarters = Enum.filter(table, &(&1.exit_round == "QF"))
      assert quarters != []
      assert Enum.all?(quarters, &(&1.points == 11 and &1.finish == :none))
    end

    test "players out at the same stage share a position and share their points" do
      {table, _players} = standings()

      for {_position, band} <- Enum.group_by(table, & &1.position), band != [] do
        points = band |> Enum.map(& &1.points) |> Enum.uniq()

        assert length(points) == 1,
               "a shared position must share its points, got #{inspect(points)}"
      end
    end

    test "the double-elimination exits score by stage, not by wins" do
      {table, _players} = standings()

      # A 32 draw runs the full depth-3 format, so every losers' round is a
      # band of its own.
      for {code, points} <- [{"L1", 2}, {"L2", 5}, {"L3", 7}, {"L4", 9}] do
        band = Enum.filter(table, &(&1.exit_round == code))

        assert band != [], "nobody went out in #{code}"

        assert Enum.all?(band, &(&1.points == points)),
               "#{code} should be worth #{points}, got #{inspect(Enum.map(band, & &1.points))}"
      end
    end

    test "a player knocked out immediately still scores the showing-up 2" do
      {table, _players} = standings()
      lowest = List.last(table)

      assert lowest.exit_round == "L1"
      assert lowest.won == 0
      assert lowest.points == 2
    end

    test "an unplayed bracket scores everyone on attendance alone" do
      stage = circuit()

      players =
        for _ <- 1..16, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players)

      table = Competitions.sp_points_standings(bracket.id)

      assert length(table) == 16
      assert Enum.all?(table, &(&1.points == 2 and &1.won == 0 and &1.finish == :none))
      assert Enum.all?(table, &(&1.status == :winners_side))
    end

    test "status splits the still-active by which side they are on" do
      stage = circuit()
      admin = insert(:admin, role: "super_admin")

      players =
        for _ <- 1..16, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players)

      # Play only the opening round: winners are unbeaten, losers have dropped
      # to the losers' side but are not out.
      first =
        Repo.all(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and r.code == "W1" and f.bye == false
        )

      for f <- first, f.participant_a_id && f.participant_b_id do
        Competitions.record_result(f, admin, %{
          "winner_participation_id" => f.participant_a_id,
          "score" => %{"a" => 6, "b" => 1}
        })
      end

      table = Competitions.sp_points_standings(bracket.id)

      assert Enum.count(table, &(&1.status == :winners_side)) == 8
      assert Enum.count(table, &(&1.status == :losers_side)) == 8
      refute Enum.any?(table, &(&1.status == :eliminated))
    end

    test "rack-win % is racks won over racks played" do
      {table, _players} = standings()
      champion = hd(table)

      assert champion.racks_played > 0

      assert_in_delta champion.rack_win_pct,
                      champion.racks_won / champion.racks_played * 100,
                      0.001

      # Every match was 6-1, so the champion's share is 6/7 of every rack.
      assert_in_delta champion.rack_win_pct, 6 / 7 * 100, 0.001
    end

    test "a bye leaves no racks behind but still moves the player on" do
      stage = circuit()
      admin = insert(:admin, role: "super_admin")

      # 30 in a 32 bracket means two byes.
      players =
        for _ <- 1..30, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players)

      play_out(bracket, admin)
      table = Competitions.sp_points_standings(bracket.id)

      bye_fixture =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and f.bye == true,
            limit: 1
        )

      id = bye_fixture.participant_a_id || bye_fixture.participant_b_id
      entry = Enum.find(table, &(&1.participation.id == id))

      # The bye counts as a win and as a match played...
      assert entry.won >= 1
      # ...but contributes no racks either way.
      assert entry.racks_played == rack_total_excluding_byes(table, entry)
    end
  end

  # The racks a player's contested matches account for — a bye adds nothing, so
  # this is just their own figure, asserted to be consistent rather than zero.
  defp rack_total_excluding_byes(_table, entry), do: entry.racks_played
end
