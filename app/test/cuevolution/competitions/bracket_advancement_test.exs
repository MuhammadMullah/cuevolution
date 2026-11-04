defmodule Cuevolution.Competitions.BracketAdvancementTest do
  @moduledoc false
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Ecto.Adapters.SQL.Sandbox

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp setup_bracket(count \\ 8, category \\ "male", opts \\ []) do
    stage = circuit()

    players =
      for _ <- 1..count, do: insert(:stage_participation, stage_id: stage.id, category: category)

    {:ok, %{bracket: bracket}} =
      Competitions.generate_circuit_bracket(stage.id, category, players, opts)

    %{bracket: bracket, players: players, admin: insert(:admin, role: "super_admin")}
  end

  defp fixture(bracket, code) do
    Repo.one!(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and f.match_id == ^("SP26-NAT-MS-" <> code)
    )
  end

  defp win(fixture, winner_id, admin) do
    {:ok, result} =
      Competitions.record_result(fixture, admin, %{
        "winner_participation_id" => winner_id,
        "score" => %{"a" => 6, "b" => 2}
      })

    result
  end

  describe "advancement on a recorded result" do
    test "the winner moves up and the loser drops to the losers' bracket" do
      %{bracket: bracket, admin: admin} = setup_bracket()

      w1 = fixture(bracket, "W1-1")
      winner = w1.participant_a_id
      loser = w1.participant_b_id

      win(w1, winner, admin)

      # Winner into Winners R2, loser into Losers R1 — both in slot "a",
      # since W1-1 is the odd match of its feeding pair.
      assert fixture(bracket, "W2-1").participant_a_id == winner
      assert fixture(bracket, "L1-1").participant_a_id == loser
    end

    test "the second match of a pair fills slot b, so both halves meet" do
      %{bracket: bracket, admin: admin} = setup_bracket()

      w1_1 = fixture(bracket, "W1-1")
      w1_2 = fixture(bracket, "W1-2")

      win(w1_1, w1_1.participant_a_id, admin)
      win(w1_2, w1_2.participant_b_id, admin)

      w2 = fixture(bracket, "W2-1")
      assert w2.participant_a_id == w1_1.participant_a_id
      assert w2.participant_b_id == w1_2.participant_b_id

      l1 = fixture(bracket, "L1-1")
      assert l1.participant_a_id == w1_1.participant_b_id
      assert l1.participant_b_id == w1_2.participant_a_id
    end

    test "losing on the losers' side advances the winner but eliminates the loser" do
      %{bracket: bracket, admin: admin} = setup_bracket()

      for code <- ["W1-1", "W1-2"] do
        f = fixture(bracket, code)
        win(f, f.participant_a_id, admin)
      end

      l1 = fixture(bracket, "L1-1")
      survivor = l1.participant_a_id
      eliminated = l1.participant_b_id

      win(l1, survivor, admin)

      # Slot B: slot A of a crossover card is reserved for whoever drops from
      # the winners' side.
      assert fixture(bracket, "L2-1").participant_b_id == survivor

      # Nobody anywhere in the bracket is holding the eliminated player.
      others =
        Repo.all(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where:
              r.knockout_bracket_id == ^bracket.id and f.id != ^l1.id and
                (f.participant_a_id == ^eliminated or f.participant_b_id == ^eliminated)
        )

      assert others
             |> Enum.map(& &1.match_id)
             |> Enum.reject(&String.starts_with?(&1, "SP26-NAT-MS-W1")) == []
    end

    test "a round-robin fixture with no bracket edges advances nothing" do
      fixture = insert(:fixture)

      assert {:ok, 0} =
               Competitions.advance_bracket(fixture, fixture.participant_a_id)
    end
  end

  describe "corrections" do
    test "re-pointing is allowed while the next match is unplayed" do
      %{bracket: bracket, admin: admin} = setup_bracket()

      w1 = fixture(bracket, "W1-1")
      first_winner = w1.participant_a_id
      other = w1.participant_b_id

      win(w1, first_winner, admin)
      assert fixture(bracket, "W2-1").participant_a_id == first_winner

      # The TD corrects who won.
      {:ok, _} = Competitions.advance_bracket(fixture(bracket, "W1-1"), other)

      assert fixture(bracket, "W2-1").participant_a_id == other
      assert fixture(bracket, "L1-1").participant_a_id == first_winner
    end

    test "a next match that has already been played is left alone" do
      %{bracket: bracket, admin: admin} = setup_bracket()

      for code <- ["W1-1", "W1-2"] do
        f = fixture(bracket, code)
        win(f, f.participant_a_id, admin)
      end

      w2 = fixture(bracket, "W2-1")
      win(w2, w2.participant_a_id, admin)

      w1 = fixture(bracket, "W1-1")

      # Correcting W1-1 now must not silently rewrite a match already played.
      assert {:ok, 0} = Competitions.advance_bracket(w1, w1.participant_b_id)
      assert fixture(bracket, "W2-1").participant_a_id == w2.participant_a_id
    end
  end

  describe "byes" do
    test "a bye pushes its player into the next round at generation time" do
      stage = circuit()

      players =
        for _ <- 1..6, do: insert(:stage_participation, stage_id: stage.id, category: "male")

      {:ok, %{bracket: bracket}} =
        Competitions.generate_circuit_bracket(stage.id, "male", players, byes: :random, rng: 3)

      byes =
        Repo.all(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and f.bye == true
        )

      assert byes != []

      for bye <- byes do
        player = bye.participant_a_id || bye.participant_b_id
        next = Repo.get!(Fixture, bye.winner_to_fixture_id)
        assert player in [next.participant_a_id, next.participant_b_id]
      end
    end
  end

  describe "live updates" do
    test "recording a result broadcasts to that bracket's other subscribers" do
      %{bracket: bracket, admin: admin} = setup_bracket()
      :ok = Competitions.subscribe_to_bracket(bracket.id)

      w1 = fixture(bracket, "W1-1")
      parent = self()

      # A different session records the result, which is the real topology:
      # one admin acts, everyone else watching is told.
      task =
        Task.async(fn ->
          Sandbox.allow(Repo, parent, self())
          win(w1, w1.participant_a_id, admin)
        end)

      Task.await(task)

      bracket_id = bracket.id
      assert_receive {:bracket_updated, ^bracket_id}
    end

    test "the session that recorded the result is not sent its own echo" do
      %{bracket: bracket, admin: admin} = setup_bracket()
      :ok = Competitions.subscribe_to_bracket(bracket.id)

      w1 = fixture(bracket, "W1-1")

      # Recorded from this very process. It has already updated as part of
      # handling the click, so echoing back would make it reload and
      # re-render the whole bracket a second time for nothing.
      win(w1, w1.participant_a_id, admin)

      refute_receive {:bracket_updated, _}, 100
    end

    test "a result on an unrelated bracket does not broadcast here" do
      %{bracket: bracket} = setup_bracket()
      other = setup_bracket(8, "female")

      :ok = Competitions.subscribe_to_bracket(bracket.id)

      f =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^other.bracket.id and f.slot == 1 and r.sequence == 1
        )

      win(f, f.participant_a_id, other.admin)

      refute_receive {:bracket_updated, _}, 100
    end
  end
end
