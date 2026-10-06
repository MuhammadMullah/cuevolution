defmodule Cuevolution.Competitions.GrassrootsDeadlineApology do
  @moduledoc """
  One-off operation for correcting the Grassroots deadline communicated to
  male Grassroots players.

  It is dry-run by default. After deployment, preview the recipients with:

      Cuevolution.Competitions.GrassrootsDeadlineApology.run()

  Dispatch the apology with:

      Cuevolution.Competitions.GrassrootsDeadlineApology.run(dry_run: false)
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.{Stage, StageParticipation}
  alias Cuevolution.Notifications
  alias Cuevolution.Repo

  @event_type :grassroots_deadline_apology
  @deadline "11 October 2026"
  @default_batch_size 50
  @default_batch_delay_ms 5_000

  @doc "Previews or dispatches the one-off deadline apology in throttled batches."
  def run(opts \\ []) when is_list(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_delay_ms = Keyword.get(opts, :batch_delay_ms, @default_batch_delay_ms)
    players = eligible_players()
    batches = Enum.chunk_every(players, batch_size)

    IO.puts("Grassroots deadline apology targets: #{length(players)}")

    Enum.with_index(batches, 1)
    |> Enum.each(fn {batch, batch_number} ->
      if dry_run do
        IO.puts("Dry run batch #{batch_number}/#{length(batches)}: #{length(batch)} players")
      else
        dispatch_batch(batch)
        IO.puts("Dispatched batch #{batch_number}/#{length(batches)}: #{length(batch)} players")
      end

      if batch_number < length(batches) and not dry_run do
        Process.sleep(batch_delay_ms)
      end
    end)

    %{dry_run: dry_run, targeted: length(players), batches: length(batches)}
  end

  defp eligible_players do
    query =
      from p in Player,
        join: sp in StageParticipation,
        on: sp.player_id == p.id,
        join: s in Stage,
        on: s.id == sp.stage_id,
        where:
          sp.category == "male" and
            s.name == "Grassroots" and
            is_nil(p.anonymized_at),
        distinct: true,
        order_by: p.id,
        select: p

    Repo.all(query)
  end

  defp dispatch_batch(players) do
    entries =
      Enum.map(players, fn player ->
        {player, %{deadline: @deadline}, "grassroots-deadline-apology:#{player.id}:2026-10-11"}
      end)

    Notifications.dispatch_many(entries, @event_type)
  end
end
