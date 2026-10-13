defmodule Cuevolution.RateLimiter do
  @moduledoc """
  Minimal in-memory fixed-window rate limiter backed by ETS.

  State is per-node and lost on restart, which is acceptable for abuse
  throttling (e.g. password-reset email requests) on the current single-VM
  deployment. If the app is ever run on multiple nodes, limits become
  per-node and this should move to a shared store.

  Callers choose the key. Count every attempt — including ones for
  identifiers that match no account — so a "limited" response can't be used
  to tell whether an account exists.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval_ms :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Records one hit against `key` and returns `:ok` while the key is within
  `limit` hits per `window_ms`, or `{:error, :rate_limited, retry_after_ms}`
  once exceeded.
  """
  @spec hit(term(), pos_integer(), pos_integer()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def hit(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    now = System.system_time(:millisecond)
    window = div(now, window_ms)
    window_end = (window + 1) * window_ms
    row_key = {key, window}

    count = :ets.update_counter(@table, row_key, {2, 1}, {row_key, 0, window_end})

    if count <= limit, do: :ok, else: {:error, :rate_limited, window_end - now}
  end

  @doc "Clears all counters. Intended for tests."
  def reset, do: :ets.delete_all_objects(@table)

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
