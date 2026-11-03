defmodule Cuevolution.Competitions.CircuitDrawTest do
  @moduledoc false
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.AdminActionLog
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp enter(count, category \\ "male") do
    stage = circuit()

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end
  end

  defp td, do: insert(:admin, role: "tournament_director")

  defp w1_participants(bracket) do
    Repo.all(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1,
        select: [f.participant_a_id, f.participant_b_id]
    )
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  describe "draw_circuit_bracket/4" do
    test "draws everyone entered into the bracket" do
      players = enter(16)
      stage = circuit()

      assert {:ok, %{entrants: 16, seed: seed}} =
               Competitions.draw_circuit_bracket(stage.id, "male", td())

      assert is_integer(seed)

      bracket = Competitions.get_knockout_bracket(stage.id, "male")
      assert Enum.sort(w1_participants(bracket)) == players |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "the same draw reference reproduces the same order" do
      enter(16)
      stage = circuit()

      {:ok, _} = Competitions.draw_circuit_bracket(stage.id, "male", td(), rng: 4242)
      first = stage.id |> Competitions.get_knockout_bracket("male") |> w1_participants()

      # Same pool, same seed, drawn again into a fresh bracket.
      other_stage = Repo.get_by!(Stage, name: "Finals")

      for p <- Competitions.circuit_entrants(stage.id, "male") do
        Repo.update!(Ecto.Changeset.change(p, stage_id: other_stage.id))
      end

      {:ok, _} =
        Competitions.draw_circuit_bracket(other_stage.id, "male", td(),
          rng: 4242,
          location_code: "NAK"
        )

      second = other_stage.id |> Competitions.get_knockout_bracket("male") |> w1_participants()

      assert first == second
    end

    test "a different reference gives a different order" do
      enter(32)
      stage = circuit()

      {:ok, _} = Competitions.draw_circuit_bracket(stage.id, "male", td(), rng: 1)
      first = stage.id |> Competitions.get_knockout_bracket("male") |> w1_participants()

      other_stage = Repo.get_by!(Stage, name: "Finals")

      for p <- Competitions.circuit_entrants(stage.id, "male") do
        Repo.update!(Ecto.Changeset.change(p, stage_id: other_stage.id))
      end

      {:ok, _} =
        Competitions.draw_circuit_bracket(other_stage.id, "male", td(),
          rng: 2,
          location_code: "NAK"
        )

      second = other_stage.id |> Competitions.get_knockout_bracket("male") |> w1_participants()

      refute first == second
    end

    test "the drawn order and reference are recorded for audit" do
      enter(8)
      stage = circuit()
      admin = td()

      {:ok, %{seed: seed}} = Competitions.draw_circuit_bracket(stage.id, "male", admin, rng: 77)

      log = Repo.one!(from l in AdminActionLog, where: l.action_type == "draw_circuit_bracket")

      assert log.admin_id == admin.id
      assert log.new_value["entrants"] == 8
      assert log.new_value["rng_seed"] == seed
      assert length(log.new_value["order"]) == 8
    end

    test "anonymized players are not drawn" do
      enter(8)
      stage = circuit()

      [first | _] = Competitions.circuit_entrants(stage.id, "male")

      Repo.update!(
        Ecto.Changeset.change(first.player,
          anonymized_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      assert {:ok, %{entrants: 7}} = Competitions.draw_circuit_bracket(stage.id, "male", td())

      bracket = Competitions.get_knockout_bracket(stage.id, "male")
      refute first.id in w1_participants(bracket)
    end

    test "refuses a field too small to draw" do
      enter(4)
      stage = circuit()

      assert {:error, :too_few_entrants} =
               Competitions.draw_circuit_bracket(stage.id, "male", td())

      assert Competitions.load_bracket(stage.id, "male") == nil
    end

    test "refuses to redraw" do
      enter(8)
      stage = circuit()

      assert {:ok, _} = Competitions.draw_circuit_bracket(stage.id, "male", td())

      assert {:error, :bracket_exists} =
               Competitions.draw_circuit_bracket(stage.id, "male", td())
    end

    test "a venue representative cannot make the national draw" do
      enter(8)
      stage = circuit()
      rep = insert(:admin, role: "venue_representative", venue_id: insert(:venue).id)

      assert {:error, :unauthorized} = Competitions.draw_circuit_bracket(stage.id, "male", rep)
      assert Competitions.load_bracket(stage.id, "male") == nil
    end

    test "two circuits cannot share a location code" do
      enter(8)
      stage = circuit()

      assert {:ok, _} =
               Competitions.draw_circuit_bracket(stage.id, "male", td(), location_code: "ELD")

      # A second circuit reusing ELD would collide on every match id, since
      # fixtures.match_id is unique across the whole competition.
      other_stage = Repo.get_by!(Stage, name: "Finals")

      for p <- Competitions.circuit_entrants(stage.id, "male") do
        Repo.update!(Ecto.Changeset.change(p, stage_id: other_stage.id))
      end

      assert {:error, :match_ids_taken} =
               Competitions.draw_circuit_bracket(other_stage.id, "male", td(),
                 location_code: "ELD"
               )

      assert {:ok, _} =
               Competitions.draw_circuit_bracket(other_stage.id, "male", td(),
                 location_code: "NAK"
               )
    end

    test "each category draws independently" do
      enter(8, "male")
      enter(8, "female")
      stage = circuit()

      assert {:ok, %{entrants: 8}} = Competitions.draw_circuit_bracket(stage.id, "male", td())
      assert {:ok, %{entrants: 8}} = Competitions.draw_circuit_bracket(stage.id, "female", td())

      ladies = Competitions.get_knockout_bracket(stage.id, "female")

      race =
        Repo.one!(
          from r in Round,
            where: r.knockout_bracket_id == ^ladies.id and r.sequence == 1,
            select: r.race_to
        )

      assert race == 4
    end
  end
end
