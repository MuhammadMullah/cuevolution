defmodule Mix.Tasks.Circuit.Reset do
  @shortdoc "Clears the Circuit draw back to its pre-draw state (dev only)"

  @moduledoc """
  Puts the Circuit stage back to the state it is in before a draw is made:
  everyone still entered, nothing drawn, nothing played.

      mix circuit.reset
      mix circuit.reset --category male
      mix circuit.reset --stage Finals

  Deletes the bracket and everything hanging off it — rounds, fixtures,
  results, frames and points entries — and leaves `stage_participations` and
  the players themselves alone, so the entrant list is exactly as it was.

  This is for rehearsing a demo end to end: draw, score, advance, repeat.
  `Competitions.reset_circuit_draw/3` is the one to use in earnest — it
  refuses once a result exists, which is the behaviour a live tournament
  wants. This task deliberately ignores that guard, which is why it refuses to
  run outside dev and test.
  """

  use Mix.Task

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.CuevoPointsEntry
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.KnockoutBracket
  alias Cuevolution.Competitions.MatchFrame
  alias Cuevolution.Competitions.MatchResult
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    if Mix.env() not in [:dev, :test] do
      Mix.raise("mix circuit.reset deletes played results and only runs in dev or test")
    end

    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [category: :string, stage: :string])

    stage_name = Keyword.get(opts, :stage, "Circuit")
    categories = List.wrap(Keyword.get(opts, :category) || ~w(male female team))

    case Repo.get_by(Stage, name: stage_name) do
      nil -> Mix.raise("No stage named #{inspect(stage_name)}")
      stage -> Enum.each(categories, &reset(stage, &1))
    end

    Mix.shell().info("")

    Enum.each(categories, fn category ->
      entrants = Competitions.circuit_entrant_count(stage_id(stage_name), category)
      Mix.shell().info("  #{String.pad_trailing(category, 7)} #{entrants} entered, none drawn")
    end)
  end

  defp stage_id(name), do: Repo.get_by!(Stage, name: name).id

  defp reset(stage, category) do
    case Repo.get_by(KnockoutBracket, stage_id: stage.id, category: category) do
      nil ->
        :ok

      bracket ->
        counts = delete_bracket(bracket)

        Mix.shell().info(
          "#{stage.name} #{category}: removed #{counts.fixtures} fixtures, " <>
            "#{counts.rounds} rounds, #{counts.results} results"
        )
    end
  end

  # Order matters: a fixture points at its result and the result points back at
  # the fixture, so the link is broken first and the dependents go before their
  # parents.
  defp delete_bracket(%KnockoutBracket{} = bracket) do
    round_ids =
      Repo.all(from r in Round, where: r.knockout_bracket_id == ^bracket.id, select: r.id)

    fixture_ids = Repo.all(from f in Fixture, where: f.round_id in ^round_ids, select: f.id)

    result_ids =
      Repo.all(from r in MatchResult, where: r.fixture_id in ^fixture_ids, select: r.id)

    Repo.transaction(fn ->
      Repo.update_all(from(f in Fixture, where: f.id in ^fixture_ids),
        set: [result_id: nil, live_score: nil]
      )

      Repo.delete_all(from e in CuevoPointsEntry, where: e.match_result_id in ^result_ids)
      Repo.delete_all(from f in MatchFrame, where: f.match_result_id in ^result_ids)
      Repo.delete_all(from r in MatchResult, where: r.id in ^result_ids)
      Repo.delete_all(from f in Fixture, where: f.id in ^fixture_ids)
      Repo.delete_all(from r in Round, where: r.id in ^round_ids)
      Repo.delete(bracket)
    end)

    %{
      fixtures: length(fixture_ids),
      rounds: length(round_ids),
      results: length(result_ids)
    }
  end
end
