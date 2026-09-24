defmodule Cuevolution.Competitions.Workers.GrassrootsDeadlineWorker do
  @moduledoc "Converts overdue scheduled Grassroots fixtures to winnerless double walkovers."

  use Oban.Worker, queue: :deadline_enforcement, max_attempts: 3

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions.{Fixture, Group, MatchResult, Round, Stage}
  alias Cuevolution.Repo
  alias Ecto.Multi

  @deadline_action "deadline_double_walkover"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    deadline = DateTime.utc_now() |> DateTime.add(3 * 60 * 60, :second) |> DateTime.to_date()

    fixtures =
      from(f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        join: g in Group,
        on: g.id == r.group_id,
        join: s in Stage,
        on: s.id == g.stage_id,
        where:
          s.name == "Grassroots" and f.status == "scheduled" and s.completion_deadline < ^deadline,
        select: f
      )
      |> Repo.all()

    Enum.reduce_while(fixtures, {:ok, 0}, fn fixture, {:ok, count} ->
      case convert_fixture(fixture) do
        {:ok, _fixture} -> {:cont, {:ok, count + 1}}
        {:skip, _reason} -> {:cont, {:ok, count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_fixture(fixture) do
    Multi.new()
    |> Multi.run(:claim, fn repo, _changes ->
      {count, _} =
        repo.update_all(
          from(f in Fixture, where: f.id == ^fixture.id and f.status == "scheduled"),
          set: [status: "walkover", walkover_kind: "double"]
        )

      if count == 1, do: {:ok, :claimed}, else: {:error, :already_processed}
    end)
    |> Multi.insert(:result, fn _changes ->
      MatchResult.system_double_walkover_changeset(%MatchResult{}, %{
        fixture_id: fixture.id,
        score: %{
          "participant_a_frames" => 0,
          "participant_b_frames" => 0,
          "points_a" => 0,
          "points_b" => 0,
          "bonus_a" => 0,
          "bonus_b" => 0,
          "walkover" => true,
          "walkover_kind" => "double"
        }
      })
    end)
    |> Multi.update(:fixture, fn %{result: result} ->
      Ecto.Changeset.change(fixture,
        result_id: result.id,
        status: "walkover",
        walkover_kind: "double"
      )
    end)
    |> Multi.run(:audit, fn _repo, %{fixture: updated} ->
      if updated.id == fixture.id do
        Accounts.log_system_action(@deadline_action, updated,
          new_value: %{walkover_kind: "double", reason: "completion_deadline"}
        )
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{fixture: updated}} -> {:ok, updated}
      {:error, :claim, :already_processed, _changes} -> {:skip, :already_processed}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end
