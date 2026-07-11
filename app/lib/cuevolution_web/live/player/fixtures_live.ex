defmodule CuevolutionWeb.FixturesLive do
  @moduledoc """
  Player fixtures & results (spec design: "My fixtures" screen).
  `Cuevolution.Competitions` (draws/match results) doesn't exist yet, so
  there's no data source at all — both lists are always empty, correctly
  showing the "no upcoming fixtures" / "no matches played yet" states.
  Swap `upcoming_fixtures/1` and `recent_results/1` for real context calls
  once draws and results are tracked.
  """
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    player = socket.assigns.current_player

    {:ok,
     assign(socket,
       page_title: "Fixtures",
       upcoming: upcoming_fixtures(player),
       results: recent_results(player)
     )}
  end

  defp ngettext_fixture(1), do: "fixture"
  defp ngettext_fixture(_count), do: "fixtures"

  # `Cuevolution.Competitions` doesn't exist yet — no draws have ever been
  # published, so there's nothing to fetch. Replace with a real query once
  # draws are tracked.
  defp upcoming_fixtures(_player), do: []

  # `Cuevolution.Competitions` doesn't exist yet — no matches have ever been
  # recorded. Replace with a real query once match results are tracked.
  defp recent_results(_player), do: []
end
