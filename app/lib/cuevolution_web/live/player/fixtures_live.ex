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
  alias Cuevolution.Repo
  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    player = Repo.preload(socket.assigns.current_player, :preferred_venue)

    {:ok,
     assign(socket,
       page_title: "Fixtures",
       upcoming: upcoming_fixtures(player),
       venue_fixtures: venue_fixtures(player),
       venue_name: player.preferred_venue && player.preferred_venue.name,
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

  defp venue_fixtures(%{preferred_venue_id: nil}), do: []

  defp venue_fixtures(player) do
    player.preferred_venue_id
    |> Competitions.upcoming_fixtures_for_venue(player.id)
    |> Enum.map(&present_venue_fixture/1)
  end

  # Grassroots auto-generated fixtures carry no `scheduled_at`/`venue_id` at
  # all (spec 012 FR-008a — players self-organize, subject only to the
  # stage-wide completion deadline). Branch here rather than assume every
  # fixture has a schedule: `fixture_time_in_eat/1` and `fixture.venue.name`
  # both raise on the nil case.
  defp present_fixture(%{scheduled_at: nil} = fixture, player) do
    {mine, opponent} = participant_sides(fixture, player)

    %{
      scheduled?: false,
      type: if(mine.category == "team", do: "Team", else: "Individual"),
      stage: String.downcase(mine.stage.name),
      opponent: Competitions.participant_name(opponent),
      opponent_phone: participant_phone(opponent),
      match_id: fixture.match_id,
      deadline: grassroots_deadline_label(fixture)
    }
  end

  defp present_fixture(fixture, player) do
    {mine, opponent} = participant_sides(fixture, player)
    eat = Competitions.fixture_time_in_eat(fixture)

    %{
      scheduled?: true,
      type: if(mine.category == "team", do: "Team", else: "Individual"),
      stage: String.downcase(mine.stage.name),
      opponent: Competitions.participant_name(opponent),
      opponent_phone: participant_phone(opponent),
      date: Calendar.strftime(eat, "%b %-d, %Y"),
      time: Calendar.strftime(eat, "%H:%M"),
      venue: fixture.venue.name
    }
  end

  defp grassroots_deadline_label(%{round: %{group: %{stage: %{completion_deadline: nil}}}}),
    do: "Not set yet"

  defp grassroots_deadline_label(%{
         round: %{group: %{stage: %{completion_deadline: deadline}}}
       }),
       do: Calendar.strftime(deadline, "%b %-d, %Y")

  defp participant_sides(fixture, player) do
    if mine?(fixture.participant_a, player) do
      {fixture.participant_a, fixture.participant_b}
    else
      {fixture.participant_b, fixture.participant_a}
    end
  end

  defp mine?(%{player_id: nil, team_id: team_id}, player), do: team_id == player.team_id
  defp mine?(%{player_id: player_id}, player), do: player_id == player.id

  defp participant_phone(%{player: %{mobile_number: mobile_number}}), do: mobile_number
  defp participant_phone(%{team: %{captain: %{mobile_number: mobile_number}}}), do: mobile_number

  defp present_venue_fixture(fixture) do
    group = fixture.round.group

    %{
      group: group.name,
      match_id: fixture.match_id,
      participant_a: Competitions.participant_name(fixture.participant_a),
      participant_b: Competitions.participant_name(fixture.participant_b),
      scheduled?: not is_nil(fixture.scheduled_at),
      date: fixture_date(fixture),
      time: fixture_time(fixture),
      deadline: venue_fixture_deadline(group)
    }
  end

  defp fixture_date(%{scheduled_at: nil}), do: nil

  defp fixture_date(%{scheduled_at: scheduled_at}),
    do: Calendar.strftime(scheduled_at, "%b %-d, %Y")

  defp fixture_time(%{scheduled_at: nil}), do: nil
  defp fixture_time(%{scheduled_at: scheduled_at}), do: Calendar.strftime(scheduled_at, "%H:%M")

  defp venue_fixture_deadline(%{stage: %{completion_deadline: nil}}), do: "Not set yet"

  defp venue_fixture_deadline(%{stage: %{completion_deadline: deadline}}),
    do: Calendar.strftime(deadline, "%b %-d, %Y")

  defp recent_results(player) do
    player.id
    |> Competitions.recent_results_for_player()
    |> Enum.map(&present_result(&1, player))
  end

  defp present_result(fixture, player) do
    opponent =
      if mine?(fixture.participant_a, player),
        do: fixture.participant_b,
        else: fixture.participant_a

    stage = fixture.round.stage.name
    double_walkover? = fixture.walkover_kind == "double"

    %{
      opponent: Competitions.participant_name(opponent),
      date: if(double_walkover?, do: "Deadline closed", else: "Result verified"),
      stage: stage,
      won:
        fixture.result &&
          fixture.result.winner_participation_id == participant_id(fixture, player),
      score: if(double_walkover?, do: "No result", else: result_score(fixture.result))
    }
  end

  defp participant_id(fixture, player) do
    if mine?(fixture.participant_a, player),
      do: fixture.participant_a_id,
      else: fixture.participant_b_id
  end

  defp result_score(%{score: score}) do
    "#{Map.get(score, "participant_a_frames", 0)}–#{Map.get(score, "participant_b_frames", 0)}"
  end
end
