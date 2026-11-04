defmodule CuevolutionWeb.StandingsRefresh do
  @moduledoc """
  Coalesces `"standings"` broadcasts into at most one reload per second.

  The standings pages reload themselves whenever a bracket result is recorded.
  That is the right behaviour and the wrong cost: a circuit runs two dozen
  tables at once, each frame tapped is a broadcast, and `/live` is public, so
  the work done per frame is multiplied by however many people are watching.
  Without a bound, a busy evening has every spectator's socket recomputing the
  whole table several times a second.

  So a burst of broadcasts becomes one reload. A second's delay is invisible on
  a scoreboard — nobody can tell a frame posted now from one posted a second
  ago — and it turns "cost per frame per viewer" into "cost per second per
  viewer", which is a number that stays put as the field and the audience grow.

  The first broadcast after mount is never delayed, so a page that has been
  sitting idle reacts at once.
  """

  import Phoenix.Component, only: [assign: 2]

  @default_interval_ms 1_000

  @doc """
  How long a burst is coalesced over. Configurable because the tests need it
  off: the `"standings"` topic is global, the standings tests run async, and
  one test's broadcast would otherwise start another test's clock and leave its
  own update deferred past the assertion.
  """
  def interval_ms do
    Application.get_env(:cuevolution, :standings_refresh_interval_ms, @default_interval_ms)
  end

  @doc "Assigns the state `refresh/2` needs. Call from `mount/3`."
  def init(socket), do: assign(socket, refresh_pending?: false, refreshed_at: nil)

  @doc """
  Reloads via `load` now, or schedules one, whichever keeps this socket inside
  one reload per second. Send the scheduled message back through `refreshed/2`.
  """
  def refresh(socket, load) when is_function(load, 1) do
    # `refreshed_at` is monotonic time, which has an arbitrary origin, so
    # "never refreshed" has to be its own value rather than a number small
    # enough to look like the distant past.
    case socket.assigns.refreshed_at do
      _any when socket.assigns.refresh_pending? -> socket
      nil -> run(socket, load)
      at -> refresh_after(socket, load, now() - at, interval_ms())
    end
  end

  defp refresh_after(socket, load, waited, interval) when waited >= interval,
    do: run(socket, load)

  defp refresh_after(socket, _load, waited, interval),
    do: schedule(socket, interval - waited)

  @doc "Handles the scheduled `:refresh_standings` message."
  def refreshed(socket, load) when is_function(load, 1), do: run(socket, load)

  @doc "The message `refresh/2` schedules, for the receiving `handle_info/2` clause."
  def message, do: :refresh_standings

  defp run(socket, load) do
    socket |> assign(refresh_pending?: false, refreshed_at: now()) |> load.()
  end

  defp schedule(socket, in_ms) do
    Process.send_after(self(), message(), in_ms)
    assign(socket, refresh_pending?: true)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
