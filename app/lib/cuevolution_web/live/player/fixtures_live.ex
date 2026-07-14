defmodule CuevolutionWeb.FixturesLive do
  @moduledoc """
  Player fixtures & results (spec design: "My fixtures" screen).

  `upcoming` is real, from `Competitions.upcoming_fixtures_for_player/1`
  (spec 007). `recent_results` stays empty — `Competitions.MatchResult`
  doesn't exist yet (spec 008), so there are no results to show; swap
  `recent_results/1` for a real query once that lands.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
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

  defp upcoming_fixtures(player) do
    player.id
    |> Competitions.upcoming_fixtures_for_player()
    |> Enum.map(&present_fixture(&1, player))
  end

  defp present_fixture(fixture, player) do
    {mine, opponent} = participant_sides(fixture, player)
    eat = Competitions.fixture_time_in_eat(fixture)

    %{
      type: if(mine.category == "team", do: "Team", else: "Individual"),
      stage: String.downcase(mine.stage.name),
      opponent: Competitions.participant_name(opponent),
      date: Calendar.strftime(eat, "%b %-d, %Y"),
      time: Calendar.strftime(eat, "%H:%M"),
      venue: fixture.venue.name
    }
  end

  defp participant_sides(fixture, player) do
    if mine?(fixture.participant_a, player) do
      {fixture.participant_a, fixture.participant_b}
    else
      {fixture.participant_b, fixture.participant_a}
    end
  end

  defp mine?(%{player_id: nil, team_id: team_id}, player), do: team_id == player.team_id
  defp mine?(%{player_id: player_id}, player), do: player_id == player.id

  # `Competitions.MatchResult` doesn't exist yet (spec 008) — no matches
  # have ever been recorded. Replace with a real query once match results
  # are tracked.
  defp recent_results(_player), do: []
end
