defmodule CuevolutionWeb.PublicMatchLive do
  @moduledoc """
  One match, shareable by link — `/m/SP26-NAT-MS-W1-6`.

  No account and no controls: a player sends this to whoever wants to follow
  the match, and it shows the two names, the running frame count while the
  match is on, and the final score once it is over. It updates itself, so a
  link sent before the match starts is still the right link an hour later.

  Deliberately free of contact details. The signed-in fixtures page shows an
  opponent's phone number so matches can be arranged; this page is served to
  anyone holding the link, and a shared scoreboard is no reason to hand out
  somebody's number.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias CuevolutionWeb.StandingsRefresh

  @impl true
  def mount(%{"match_id" => match_id}, _session, socket) do
    case Competitions.fixture_by_match_id(match_id) do
      nil ->
        {:ok,
         socket
         |> assign(page_title: "Match not found", match_id: match_id, fixture: nil)
         |> StandingsRefresh.init()}

      fixture ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

        {:ok,
         socket
         |> assign(page_title: match_title(fixture), match_id: match_id)
         |> StandingsRefresh.init()
         |> assign(fixture: fixture)}
    end
  end

  @impl true
  def handle_info({:points_updated, _id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp load(socket) do
    assign(socket, fixture: Competitions.fixture_by_match_id(socket.assigns.match_id))
  end

  defp match_title(fixture) do
    "#{side_name(fixture.participant_a)} v #{side_name(fixture.participant_b)}"
  end

  # ---------------------------------------------------------------- display

  @doc false
  def side_name(nil), do: "To be decided"

  def side_name(%{player: %{first_name: first, last_name: last}}),
    do: Names.full_name(first, last)

  def side_name(%{team: %{name: name}}), do: name
  def side_name(_other), do: "To be decided"

  @doc false
  def side_score(%{result: %{score: %{} = final}}, side), do: frames(final, side)
  def side_score(%{live_score: %{} = live}, side), do: frames(live, side)
  def side_score(_fixture, _side), do: nil

  defp frames(score, side) do
    Map.get(score, side) ||
      Map.get(score, if(side == "a", do: "participant_a_frames", else: "participant_b_frames"))
  end

  @doc false
  def won?(%{result: %{winner_participation_id: id}} = fixture, "a") when is_binary(id),
    do: fixture.participant_a_id == id

  def won?(%{result: %{winner_participation_id: id}} = fixture, "b") when is_binary(id),
    do: fixture.participant_b_id == id

  def won?(_fixture, _side), do: false

  @doc false
  def state(%{status: status}) when status in ["completed", "verified"], do: :final
  def state(%{status: "walkover"}), do: :walkover
  def state(%{status: "live"}), do: :live
  def state(_fixture), do: :upcoming

  @doc false
  def state_label(fixture) do
    case state(fixture) do
      :final -> "Final"
      :walkover -> "Walkover"
      :live -> "Live"
      :upcoming -> "Upcoming"
    end
  end

  @doc false
  def start_label(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> nil
      start -> Calendar.strftime(start, "%a %-d %b, %H:%M")
    end
  end
end
