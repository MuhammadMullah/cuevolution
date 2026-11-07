defmodule Cuevolution.Competitions.MatchCaptureTest do
  @moduledoc """
  The match data the SP Points & Standings brief asks to be recorded on every
  match, and the one rule that depends on it: byes and walkovers stay out of
  the rack columns.
  """
  use Cuevolution.DataCase, async: true

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp drawn(count \\ 32) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: "male")
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, "male", admin)
    %{bracket: bracket, admin: admin}
  end

  defp opener(bracket) do
    Repo.one!(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where:
          r.knockout_bracket_id == ^bracket.id and r.code == "W1" and f.bye == false and
            not is_nil(f.participant_a_id) and not is_nil(f.participant_b_id),
        limit: 1
    )
  end

  describe "result type" do
    test "it is derived from the fixture, never stored" do
      %{bracket: bracket, admin: admin} = drawn()
      fixture = opener(bracket)

      assert Competitions.result_type(fixture) == :played

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      assert Competitions.result_type(Repo.get!(Fixture, fixture.id)) == :played
    end

    test "a bye is a bye" do
      # 30 in a 32 bracket leaves two byes.
      %{bracket: bracket} = drawn(30)

      bye =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and f.bye == true,
            limit: 1
        )

      assert Competitions.result_type(bye) == :bye
    end
  end

  describe "the round carries its bracket side and code" do
    test "every bracket round is identified by both" do
      %{bracket: bracket} = drawn()

      rounds =
        Repo.all(
          from r in Round, where: r.knockout_bracket_id == ^bracket.id, order_by: r.sequence
        )

      assert Enum.all?(rounds, &(&1.code not in [nil, ""]))
      assert Enum.all?(rounds, &(&1.bracket_side in ~w(winners losers knockout)))

      codes = Enum.map(rounds, & &1.code)
      assert "W2" in codes
      assert "L2" in codes
      assert List.last(codes) == "F"
    end
  end

  describe "optional capture fields" do
    test "a table number is saved with the start time" do
      %{bracket: bracket, admin: admin} = drawn()
      fixture = opener(bracket)

      {:ok, updated} =
        Competitions.schedule_bracket_fixture(fixture, admin, %{
          "date" => Date.to_iso8601(Competitions.today_in_eat()),
          "time" => "14:30",
          "table_number" => "7"
        })

      assert updated.table_number == 7
    end

    test "a blank or nonsense table number clears it rather than failing the save" do
      %{bracket: bracket, admin: admin} = drawn()
      fixture = opener(bracket)

      for value <- ["", "   ", "abc", "0", "-3"] do
        {:ok, updated} =
          Competitions.schedule_bracket_fixture(fixture, admin, %{
            "date" => Date.to_iso8601(Competitions.today_in_eat()),
            "time" => "14:30",
            "table_number" => value
          })

        assert updated.table_number == nil, "#{inspect(value)} should clear the table number"
      end
    end

    test "the end time is stamped when the result is recorded" do
      %{bracket: bracket, admin: admin} = drawn()
      fixture = opener(bracket)

      assert fixture.ended_at == nil

      {:ok, _} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => 2}
        })

      assert %DateTime{} = Repo.get!(Fixture, fixture.id).ended_at
    end
  end

  describe "byes and walkovers stay out of the rack columns" do
    test "a bye adds a match and a win but no racks" do
      %{bracket: bracket, admin: admin} = drawn(30)

      bye =
        Repo.one!(
          from f in Fixture,
            join: r in Round,
            on: r.id == f.round_id,
            where: r.knockout_bracket_id == ^bracket.id and f.bye == true,
            limit: 1
        )

      id = bye.participant_a_id || bye.participant_b_id

      # Play nothing else, so this player's only match is the bye.
      row =
        bracket.id
        |> Competitions.sp_points_standings()
        |> Enum.find(&(&1.participation.id == id))

      assert row.won == 1, "a bye counts as a win"
      assert row.played == 1
      assert row.racks_won == 0
      assert row.racks_played == 0
      assert row.rack_win_pct == nil, "no racks played means no percentage"

      # And it still moved them on, so they are unbeaten.
      assert row.status == :winners_side
      refute is_nil(admin)
    end
  end
end
