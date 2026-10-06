defmodule Cuevolution.Competitions.Workers.GrassrootsDeadlineWorker do
  @moduledoc "Converts overdue scheduled Grassroots fixtures to winnerless double walkovers."

  use Oban.Worker, queue: :deadline_enforcement, max_attempts: 3

  import Ecto.Query

  alias Cuevolution.Accounts.AdminActionLog
  alias Cuevolution.Competitions.{Fixture, Group, MatchResult, Round, Stage}
  alias Cuevolution.Repo

  @deadline_action "deadline_double_walkover"

  @double_walkover_score %{
    "participant_a_frames" => 0,
    "participant_b_frames" => 0,
    "points_a" => 0,
    "points_b" => 0,
    "bonus_a" => 0,
    "bonus_b" => 0,
    "walkover" => true,
    "walkover_kind" => "double"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    deadline = DateTime.utc_now() |> DateTime.add(3 * 60 * 60, :second) |> DateTime.to_date()

    fixture_ids =
      from(f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        join: g in Group,
        on: g.id == r.group_id,
        join: s in Stage,
        on: s.id == g.stage_id,
        where:
          s.name == "Grassroots" and f.status == "scheduled" and s.completion_deadline < ^deadline,
        select: f.id
      )
      |> Repo.all()

    convert_fixtures(fixture_ids)

    :ok
  end

  # Batched the same way as the draw/fixture-generation fix: claiming,
  # recording a result, and auditing each of potentially hundreds of
  # overdue fixtures one at a time (the original approach) ran 4
  # sequential round trips per fixture in its own transaction. This does
  # it in 4 round trips total regardless of how many fixtures are overdue
  # — one claiming update, one result insert, one fixture-result backfill
  # (each fixture needs its own freshly-created result's id, via a
  # one-shot `unnest` join instead of N single-row updates), one audit
  # insert.
  defp convert_fixtures([]), do: :ok

  defp convert_fixtures(fixture_ids) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {_count, claimed_ids} =
      Fixture
      |> where([f], f.id in ^fixture_ids and f.status == "scheduled")
      |> select([f], f.id)
      |> Repo.update_all(set: [status: "walkover", walkover_kind: "double", updated_at: now])

    if claimed_ids != [] do
      result_ids_by_fixture = Map.new(claimed_ids, &{&1, Ecto.UUID.generate()})

      insert_results(result_ids_by_fixture, now)
      backfill_fixture_result_ids(result_ids_by_fixture, now)
      insert_audit_logs(claimed_ids, now)
    end
  end

  defp insert_results(result_ids_by_fixture, now) do
    rows =
      Enum.map(result_ids_by_fixture, fn {fixture_id, result_id} ->
        %{
          id: result_id,
          fixture_id: fixture_id,
          score: @double_walkover_score,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(MatchResult, rows)
  end

  defp backfill_fixture_result_ids(result_ids_by_fixture, now) do
    {fixture_ids, result_ids} = Enum.unzip(result_ids_by_fixture)

    from(f in Fixture,
      join:
        v in fragment(
          "SELECT * FROM unnest(?::text[], ?::text[]) AS t(fixture_id, result_id)",
          ^fixture_ids,
          ^result_ids
        ),
      on: v.fixture_id == fragment("?::text", f.id),
      update: [
        set: [
          result_id: type(fragment("?::uuid", v.result_id), Ecto.UUID),
          updated_at: ^now
        ]
      ]
    )
    |> Repo.update_all([])
  end

  defp insert_audit_logs(fixture_ids, now) do
    entity_type = Fixture |> to_string() |> String.trim_leading("Elixir.")

    rows =
      Enum.map(fixture_ids, fn fixture_id ->
        %{
          id: Ecto.UUID.generate(),
          actor_type: "system",
          action_type: @deadline_action,
          entity_type: entity_type,
          entity_id: fixture_id,
          new_value: %{"walkover_kind" => "double", "reason" => "completion_deadline"},
          inserted_at: now
        }
      end)

    Repo.insert_all(AdminActionLog, rows)
  end
end
