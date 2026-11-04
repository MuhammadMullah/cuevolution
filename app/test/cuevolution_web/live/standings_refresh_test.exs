defmodule CuevolutionWeb.StandingsRefreshTest do
  @moduledoc """
  The coalescing itself, tested directly. The LiveView tests run with the
  interval at 0 (see `config/test.exs`), so this is where the branches that
  bound a busy circuit's reload rate are actually covered.
  """
  use ExUnit.Case, async: true

  alias CuevolutionWeb.StandingsRefresh

  # A socket is only ever read through `assign/2` and `socket.assigns` here, so
  # a bare struct with an assigns map is enough.
  defp socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

  defp counting_load do
    owner = self()
    fn socket -> send(owner, :loaded) && socket end
  end

  defp loaded? do
    receive do
      :loaded -> true
    after
      0 -> false
    end
  end

  defp with_interval(ms, fun) do
    previous = Application.get_env(:cuevolution, :standings_refresh_interval_ms)
    Application.put_env(:cuevolution, :standings_refresh_interval_ms, ms)

    try do
      fun.()
    after
      Application.put_env(:cuevolution, :standings_refresh_interval_ms, previous)
    end
  end

  describe "init/1" do
    test "starts with nothing pending and no previous refresh" do
      assigns = socket() |> StandingsRefresh.init() |> Map.fetch!(:assigns)

      assert assigns.refresh_pending? == false
      assert assigns.refreshed_at == nil
    end
  end

  describe "refresh/2" do
    test "the first broadcast after mount is never delayed" do
      socket = socket() |> StandingsRefresh.init() |> StandingsRefresh.refresh(counting_load())

      assert loaded?(), "an idle page must react at once"
      assert socket.assigns.refresh_pending? == false
      assert is_integer(socket.assigns.refreshed_at)
    end

    test "a second broadcast inside the window is deferred, not dropped" do
      with_interval(1_000, fn ->
        socket =
          socket()
          |> StandingsRefresh.init()
          |> StandingsRefresh.refresh(counting_load())

        assert loaded?()

        socket = StandingsRefresh.refresh(socket, counting_load())

        refute loaded?(), "the second broadcast should not have reloaded yet"
        assert socket.assigns.refresh_pending?
        assert_receive :refresh_standings, 2_000
      end)
    end

    test "further broadcasts while one is pending schedule nothing more" do
      with_interval(1_000, fn ->
        socket =
          socket()
          |> StandingsRefresh.init()
          |> StandingsRefresh.refresh(counting_load())

        assert loaded?()

        socket = StandingsRefresh.refresh(socket, counting_load())
        assert socket.assigns.refresh_pending?

        # Five more frames in the same second must still be one reload.
        socket =
          Enum.reduce(1..5, socket, fn _i, acc ->
            StandingsRefresh.refresh(acc, counting_load())
          end)

        assert socket.assigns.refresh_pending?
        assert_receive :refresh_standings, 2_000
        refute_receive :refresh_standings, 200
      end)
    end

    test "a broadcast after the window has passed runs straight away" do
      with_interval(0, fn ->
        socket =
          socket()
          |> StandingsRefresh.init()
          |> StandingsRefresh.refresh(counting_load())

        assert loaded?()

        StandingsRefresh.refresh(socket, counting_load())
        assert loaded?(), "past the window there is nothing to coalesce"
      end)
    end
  end

  describe "refreshed/2" do
    test "the deferred reload runs and clears the pending flag" do
      socket =
        %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, refresh_pending?: true, refreshed_at: 0}
        }
        |> StandingsRefresh.refreshed(counting_load())

      assert loaded?()
      assert socket.assigns.refresh_pending? == false
    end
  end

  test "message/0 is what refresh/2 schedules" do
    assert StandingsRefresh.message() == :refresh_standings
  end
end
