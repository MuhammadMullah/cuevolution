defmodule CuevolutionWeb.FixturesLive do
  @moduledoc """
  Player fixtures & results (spec design: "My fixtures" screen).

  `upcoming` is real, from `Competitions.upcoming_fixtures_for_player/1`
  (spec 007). `recent_results` stays empty — `Competitions.MatchResult`
  doesn't exist yet (spec 008), so there are no results to show; swap
  `recent_results/1` for a real query once that lands.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo
  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    player = Repo.preload(socket.assigns.current_player, :preferred_venue)
    all_upcoming = upcoming_fixtures(player)
    all_results = recent_results(player)

    {:ok,
     assign(socket,
       page_title: "Fixtures",
       all_upcoming: all_upcoming,
       all_results: all_results,
       upcoming: all_upcoming,
       results: all_results,
       stage_filter: nil,
       stage_options: stage_options(all_upcoming, all_results),
       venue_fixtures: venue_fixtures(player),
       venue_name: player.preferred_venue && player.preferred_venue.name,
       venue_representative: Accounts.venue_representative_for_venue(player.preferred_venue_id)
     )}
  end

  def handle_event("filter_stage", %{"stage" => stage}, socket) do
    stage_filter = if stage == "", do: nil, else: stage

    {:noreply,
     assign(socket,
       stage_filter: stage_filter,
       upcoming: filter_by_stage(socket.assigns.all_upcoming, stage_filter),
       results: filter_by_stage(socket.assigns.all_results, stage_filter)
     )}
  end

  defp ngettext_fixture(1), do: "fixture"
  defp ngettext_fixture(_count), do: "fixtures"

  # Pipeline order (Grassroots → ... → Finals), limited to stages the player
  # actually has upcoming fixtures or results in. `result.stage` keeps its
  # original casing for display (see `present_result/2`), so compare
  # case-insensitively here.
  defp stage_options(upcoming, results) do
    present = MapSet.new(upcoming ++ results, &String.downcase(&1.stage))

    Competitions.list_stages()
    |> Enum.map(&String.downcase(&1.name))
    |> Enum.filter(&MapSet.member?(present, &1))
  end

  defp filter_by_stage(fixtures, nil), do: fixtures

  defp filter_by_stage(fixtures, stage),
    do: Enum.filter(fixtures, &(String.downcase(&1.stage) == stage))

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

  # Three shapes of fixture reach this page and they disagree about what they
  # have. A Grassroots fixture has neither a time nor a venue — players
  # self-organize against a stage deadline (spec 012 FR-008a). A Circuit
  # fixture has a time once the TD sets one, but never a venue, and belongs to
  # a bracket rather than a group, so it has no deadline to show either. One
  # function, with every absence handled, rather than a clause per shape that
  # raises the first time a new shape turns up.
  defp present_fixture(fixture, player) do
    {mine, opponent} = participant_sides(fixture, player)
    eat = fixture.scheduled_at && Competitions.fixture_time_in_eat(fixture)

    %{
      scheduled?: not is_nil(eat),
      type: if(mine.category == "team", do: "Team", else: "Individual"),
      stage: String.downcase(fixture.round.stage.name),
      opponent: opponent_name(opponent),
      opponent_phone: participant_phone(opponent),
      match_id: fixture.match_id,
      date: eat && Calendar.strftime(eat, "%b %-d, %Y"),
      time: eat && Calendar.strftime(eat, "%H:%M"),
      venue: venue_label(fixture),
      deadline: deadline_label(fixture)
    }
  end

  # Only the round-robin stages run to a self-organized deadline. A Circuit
  # match is scheduled by the tournament director, so until they set a time
  # there is nothing to count down to.
  defp deadline_label(fixture) do
    if Stage.round_robin?(fixture.round.stage),
      do: group_deadline_label(fixture),
      else: "To be scheduled"
  end

  defp group_deadline_label(%{round: %{group: %{stage: %{completion_deadline: nil}}}}),
    do: "Not set yet"

  defp group_deadline_label(%{round: %{group: %{stage: %{completion_deadline: deadline}}}}),
    do: Calendar.strftime(deadline, "%b %-d, %Y")

  defp group_deadline_label(_fixture), do: "Not set yet"

  defp venue_label(%{venue: %{name: name}}), do: name
  defp venue_label(_fixture), do: "Venue to be confirmed"

  # A knockout fixture has an empty slot until the match that feeds it is
  # played, so the player can be looking at a real upcoming match whose
  # opponent does not exist yet. `Competitions.participant_name/1` takes a
  # participation and is right to stay strict about it.
  defp opponent_name(nil), do: "To be decided"
  defp opponent_name(participant), do: Competitions.participant_name(participant)

  defp participant_sides(fixture, player) do
    if mine?(fixture.participant_a, player) do
      {fixture.participant_a, fixture.participant_b}
    else
      {fixture.participant_b, fixture.participant_a}
    end
  end

  defp mine?(nil, _player), do: false
  defp mine?(%{player_id: nil, team_id: team_id}, player), do: team_id == player.team_id
  defp mine?(%{player_id: player_id}, player), do: player_id == player.id

  defp participant_phone(%{player: %{mobile_number: mobile_number}}), do: mobile_number
  defp participant_phone(%{team: %{captain: %{mobile_number: mobile_number}}}), do: mobile_number
  defp participant_phone(_participant), do: nil

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
      opponent: opponent_name(opponent),
      date: result_label(fixture, double_walkover?),
      match_id: fixture.match_id,
      stage: stage,
      outcome: result_outcome(fixture, player, double_walkover?),
      score: if(double_walkover?, do: "No result", else: result_score(fixture.result))
    }
  end

  # "Verified" is the round-robin stages' wording — it means a TD approved the
  # result. A Circuit result is final when recorded, so saying it was verified
  # would describe a step that never happened.
  defp result_label(_fixture, true), do: "Deadline closed"
  defp result_label(%{status: "verified"}, false), do: "Result verified"
  defp result_label(%{status: "walkover"}, false), do: "Walkover"
  defp result_label(_fixture, false), do: "Result recorded"

  # Neither a win nor a loss for either side: a deadline double walkover, or
  # (Regional's 4-frame format only) a genuine 2-2 draw.
  defp result_outcome(_fixture, _player, true), do: :drawn

  defp result_outcome(fixture, player, false) do
    cond do
      is_nil(fixture.result.winner_participation_id) -> :drawn
      fixture.result.winner_participation_id == participant_id(fixture, player) -> :won
      true -> :lost
    end
  end

  def outcome_letter(:won), do: "W"
  def outcome_letter(:lost), do: "L"
  def outcome_letter(:drawn), do: "D"

  def outcome_word(:won), do: "Won"
  def outcome_word(:lost), do: "Lost"
  def outcome_word(:drawn), do: "Drawn"

  defp participant_id(fixture, player) do
    if mine?(fixture.participant_a, player),
      do: fixture.participant_a_id,
      else: fixture.participant_b_id
  end

  # The round-robin stages store `participant_a_frames`/`participant_b_frames`;
  # the Circuit stores `a`/`b`, keyed by the side of the card.
  defp result_score(%{score: score}) do
    {a, b} = score_frames(score)
    "#{a}–#{b}"
  end

  defp score_frames(%{"participant_a_frames" => a, "participant_b_frames" => b}), do: {a, b}
  defp score_frames(%{"a" => a, "b" => b}), do: {a, b}
  defp score_frames(_score), do: {0, 0}
end
