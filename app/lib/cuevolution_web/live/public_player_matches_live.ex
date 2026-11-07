defmodule CuevolutionWeb.PublicPlayerMatchesLive do
  @moduledoc """
  Every match of one player, shareable by link — `/p/their-username`.

  This is the link a player sends so family, a club or a sponsor can follow
  their whole run: upcoming matches first, then everything already played,
  across every stage. Each row links on to that match's own page.

  Keyed on username because it is already the player's public handle — it
  appears in the directory and on the draw sheet — so the link is readable and
  stays the same. Like `PublicMatchLive`, it carries no contact details.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias CuevolutionWeb.PublicMatchLive
  alias CuevolutionWeb.StandingsRefresh

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_player_by_username(username) do
      nil ->
        {:ok,
         socket
         |> assign(page_title: "Player not found", username: username, player: nil, matches: [])
         |> StandingsRefresh.init()}

      player ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

        {:ok,
         socket
         |> assign(
           page_title: Names.player_name(player),
           username: username,
           player: player
         )
         |> StandingsRefresh.init()
         |> load()}
    end
  end

  @impl true
  def handle_info({:points_updated, _id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp load(%{assigns: %{player: nil}} = socket), do: socket

  # Every row is presented here rather than in the template. A `<% x = ... %>`
  # assignment in HEEx defeats change tracking for its whole block, which on a
  # page that reloads itself as frames land means re-sending the entire list
  # on every update.
  defp load(socket) do
    player = socket.assigns.player
    matches = Competitions.public_matches_for_player(player.id)

    assign(socket,
      matches: Enum.map(matches, &present(&1, player)),
      played: Enum.count(matches, &(not is_nil(&1.result_id)))
    )
  end

  defp present(fixture, player) do
    {mine, opponent, my_side, their_side} = sides(fixture, player)
    outcome = outcome(fixture, mine)

    %{
      match_id: fixture.match_id,
      state: state(fixture),
      state_label: state_label(fixture),
      stage: fixture.round.stage.name,
      round: Competitions.match_round_label(fixture),
      start: start_label(fixture),
      mine: side_name(mine),
      opponent: side_name(opponent),
      my_score: side_score(fixture, my_side) || 0,
      their_score: side_score(fixture, their_side) || 0,
      outcome: outcome,
      outcome_letter: outcome_letter(outcome)
    }
  end

  # ---------------------------------------------------------------- display

  # The player's own side of a fixture, and their opponent's. A team match is
  # theirs through their team, so neither side is matched on `player_id` alone.
  defp sides(fixture, player) do
    if mine?(fixture.participant_a, player),
      do: {fixture.participant_a, fixture.participant_b, "a", "b"},
      else: {fixture.participant_b, fixture.participant_a, "b", "a"}
  end

  defp mine?(%{player_id: nil, team_id: team_id}, player), do: team_id == player.team_id
  defp mine?(%{player_id: player_id}, player), do: player_id == player.id
  defp mine?(_participant, _player), do: false

  defp outcome(%{result: nil}, _mine), do: nil
  defp outcome(%{result: %{winner_participation_id: nil}}, _mine), do: :drawn

  defp outcome(%{result: %{winner_participation_id: id}}, mine),
    do: if(mine && mine.id == id, do: :won, else: :lost)

  defp outcome_letter(:won), do: "W"
  defp outcome_letter(:lost), do: "L"
  defp outcome_letter(:drawn), do: "D"
  defp outcome_letter(_other), do: nil

  defp side_name(participant), do: PublicMatchLive.side_name(participant)
  defp side_score(fixture, side), do: PublicMatchLive.side_score(fixture, side)
  defp state(fixture), do: PublicMatchLive.state(fixture)
  defp state_label(fixture), do: PublicMatchLive.state_label(fixture)
  defp start_label(fixture), do: PublicMatchLive.start_label(fixture)
end
