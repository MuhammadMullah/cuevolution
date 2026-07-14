defmodule Cuevolution.CompetitionsConcurrencyTest do
  # Spawns real processes hitting the same DB connection concurrently, so the
  # sandbox needs shared mode (DataCase enables that automatically for
  # async: false).
  use Cuevolution.DataCase, async: false

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig

  test "concurrent advance_to_stage/2 calls at the last remaining capacity slot: exactly one succeeds" do
    circuit = Repo.get_by!(Stage, name: "Circuit")
    finals = Repo.get_by!(Stage, name: "Finals")
    config = Repo.get_by!(StageCapacityConfig, stage_id: finals.id, category: "male")

    Repo.update_all(
      from(c in StageCapacityConfig, where: c.id == ^config.id),
      set: [current_count: config.capacity_limit - 1]
    )

    participations =
      for _ <- 1..5,
          do: insert(:stage_participation, stage_id: circuit.id, category: "male")

    results =
      participations
      |> Task.async_stream(fn p -> Competitions.advance_to_stage(p, finals) end,
        max_concurrency: 5,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &(&1 == {:error, :capacity_exceeded}))

    assert successes == 1
    assert failures == 4
    assert Repo.get!(StageCapacityConfig, config.id).current_count == config.capacity_limit
  end
end
