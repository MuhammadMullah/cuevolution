defmodule Cuevolution.Competitions.ReshapeCircuitBracketTest do
  @moduledoc """
  `Competitions.reshape_circuit_bracket/2` — converting a men's bracket drawn
  three winners' rounds deep (as Circuit 1 in Eldoret was) back to the agreed
  two-round format mid-event, without losing anything already played.
  """
  use Cuevolution.DataCase, async: true

  @moduletag timeout: 300_000

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  # The production situation: a 128 men's bracket drawn at depth 3, with
  # WB R1 and LB R1 finished, part of WB R2 played and one WB R2 match live.
  defp deep_bracket_mid_event(_context) do
    stage = circuit()
    admin = insert(:admin, role: "super_admin")

    players =
      for _ <- 1..128, do: insert(:stage_participation, stage_id: stage.id, category: "male")

    {:ok, %{bracket: bracket}} =
      Competitions.generate_circuit_bracket(stage.id, "male", players, depth: 3)

    play_round(bracket, admin, "W1")
    play_round(bracket, admin, "L1")
    play_round(bracket, admin, "W2", limit: 20)

    live = fixture(bracket, "W2", 25)

    Repo.update_all(from(f in Fixture, where: f.id == ^live.id),
      set: [live_score: %{"a" => 3, "b" => 2}, status: "live"]
    )

    %{bracket: bracket, admin: admin, live_id: live.id}
  end

  describe "a depth-3 men's bracket in the middle of WB R2" do
    setup :deep_bracket_mid_event

    test "a dry run reports the change and leaves the bracket untouched", %{bracket: bracket} do
      before = snapshot(bracket)

      assert {:ok, summary} = Competitions.reshape_circuit_bracket(bracket.id, dry_run: true)
      assert summary.dry_run
      assert summary.removed_rounds == ~w(W3 L3 L4 R32 R16 QF SF F)
      assert summary.added_rounds == ~w(R64 R32 R16 QF SF F)
      assert length(summary.advanced) == 20

      assert snapshot(bracket) == before
    end

    test "it becomes the agreed format, keeping every result, live score and match id",
         %{bracket: bracket, live_id: live_id} do
      kept_before = kept_fixtures(bracket)

      assert {:ok, summary} = Competitions.reshape_circuit_bracket(bracket.id)
      refute Map.get(summary, :dry_run)

      assert round_codes(bracket) == ~w(W1 W2 L1 L2 R64 R32 R16 QF SF F)

      assert Repo.one(
               from r in Round,
                 where: r.knockout_bracket_id == ^bracket.id,
                 select: max(r.sequence)
             ) == 10

      # Every fixture in WB R1-R2 and LB R1-R2 is the same row with the same
      # players, result, status, live score, match id and routing — except
      # where WB R2 and LB R2 send their winners, which is the point.
      assert kept_fixtures(bracket) |> Map.new(&{&1.id, comparable(&1, :kept)}) ==
               Map.new(kept_before, &{&1.id, comparable(&1, :kept)})

      live = Repo.get!(Fixture, live_id)
      assert live.live_score == %{"a" => 3, "b" => 2}
      assert live.status == "live"

      # The new round of 64 races to 6, like the rest of the knockout.
      assert Repo.get_by!(Round, knockout_bracket_id: bracket.id, code: "R64").race_to == 6
    end

    test "WB R2 winners already decided are moved straight into the round of 64",
         %{bracket: bracket} do
      {:ok, _} = Competitions.reshape_circuit_bracket(bracket.id)

      for k <- 1..32 do
        w2 = fixture(bracket, "W2", k) |> Repo.preload(:result)
        r64 = fixture(bracket, "R64", k)

        assert w2.winner_to_fixture_id == r64.id
        assert w2.winner_to_side == "a"

        if w2.result do
          assert r64.participant_a_id == w2.result.winner_participation_id
        else
          assert r64.participant_a_id == nil
        end
      end

      # LB R2 survivors arrive in slot B, rotated half a round.
      assert fixture(bracket, "L2", 1).winner_to_fixture_id == fixture(bracket, "R64", 17).id
      assert fixture(bracket, "L2", 1).winner_to_side == "b"

      # WB R2 losers still drop into LB R2, mirrored, exactly as before.
      assert fixture(bracket, "W2", 1).loser_to_fixture_id == fixture(bracket, "L2", 32).id
    end

    test "the rest of the event then plays through to a 46-point champion",
         %{bracket: bracket, admin: admin} do
      {:ok, _} = Competitions.reshape_circuit_bracket(bracket.id)

      Repo.update_all(from(f in Fixture, where: f.status == "live"),
        set: [live_score: nil, status: "scheduled"]
      )

      for code <- ~w(W2 L2 R64 R32 R16 QF SF F), do: play_round(bracket, admin, code)

      r64 = fixtures_in(bracket, "R64")
      players = Enum.flat_map(r64, &[&1.participant_a_id, &1.participant_b_id])
      assert length(Enum.uniq(players)) == 64
      refute nil in players

      table = Competitions.sp_points_standings(bracket.id)
      assert hd(table).finish == :champion
      assert hd(table).points == 46

      out_in_r64 = Enum.filter(table, &(&1.exit_round == "R64"))
      assert length(out_in_r64) == 32
      assert Enum.all?(out_in_r64, &(&1.points == 9 and &1.position == {33, 64}))
    end

    test "a second run has nothing to do", %{bracket: bracket} do
      {:ok, _} = Competitions.reshape_circuit_bracket(bracket.id)
      assert {:error, :already_in_format} = Competitions.reshape_circuit_bracket(bracket.id)
    end
  end

  test "it refuses, changing nothing, once a match it would remove has been played" do
    %{bracket: bracket, admin: admin} = deep_bracket_mid_event(%{})

    # W2-1 and W2-2 are among the 20 played, so W3-1 has both players.
    w3 = fixture(bracket, "W3", 1)

    {:ok, _} =
      Competitions.record_result(w3, admin, %{
        "winner_participation_id" => w3.participant_a_id,
        "score" => %{"a" => 6, "b" => 1}
      })

    before = snapshot(bracket)

    assert {:error, {:played_fixtures_would_be_removed, ["W3-1"]}} =
             Competitions.reshape_circuit_bracket(bracket.id)

    assert snapshot(bracket) == before
  end

  test "a bracket already in the agreed format is left alone" do
    stage = circuit()

    players =
      for _ <- 1..16, do: insert(:stage_participation, stage_id: stage.id, category: "male")

    {:ok, %{bracket: bracket}} = Competitions.generate_circuit_bracket(stage.id, "male", players)

    assert {:error, :already_in_format} = Competitions.reshape_circuit_bracket(bracket.id)
  end

  # ------------------------------------------------------------------ helpers

  defp play_round(bracket, admin, code, opts \\ []) do
    bracket
    |> fixtures_in(code)
    |> Enum.filter(&(&1.participant_a_id && &1.participant_b_id && is_nil(&1.result_id)))
    |> Enum.take(Keyword.get(opts, :limit, 1_000))
    |> Enum.each(fn f ->
      {:ok, _} =
        Competitions.record_result(Repo.get!(Fixture, f.id), admin, %{
          "winner_participation_id" => f.participant_a_id,
          "score" => %{"a" => 6, "b" => 1}
        })
    end)
  end

  defp fixtures_in(bracket, code) do
    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and r.code == ^code,
        order_by: [asc: f.slot]
    )
  end

  defp fixture(bracket, code, slot),
    do: bracket |> fixtures_in(code) |> Enum.find(&(&1.slot == slot))

  defp round_codes(bracket) do
    Repo.all(
      from r in Round,
        where: r.knockout_bracket_id == ^bracket.id,
        order_by: [asc: r.sequence],
        select: r.code
    )
  end

  defp kept_fixtures(bracket), do: Enum.flat_map(~w(W1 W2 L1 L2), &fixtures_in(bracket, &1))

  # WB R2 and LB R2 winner routes are the one thing in the kept rounds that
  # should change: they now lead into the round of 64.
  defp comparable(f, :kept) do
    if String.contains?(f.match_id, ["-W2-", "-L2-"]),
      do: Map.drop(comparable(f), [:winner_to_fixture_id, :winner_to_side]),
      else: comparable(f)
  end

  defp comparable(f) do
    Map.take(f, [
      :match_id,
      :participant_a_id,
      :participant_b_id,
      :result_id,
      :status,
      :live_score,
      :scheduled_at,
      :winner_to_fixture_id,
      :winner_to_side,
      :loser_to_fixture_id,
      :loser_to_side
    ])
  end

  defp snapshot(bracket) do
    rounds =
      Repo.all(from r in Round, where: r.knockout_bracket_id == ^bracket.id, order_by: r.sequence)

    fixtures =
      Repo.all(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where: r.knockout_bracket_id == ^bracket.id,
          order_by: [asc: f.id]
      )

    {Enum.map(rounds, &{&1.id, &1.code, &1.sequence}),
     Enum.map(fixtures, &{&1.id, comparable(&1)})}
  end
end
