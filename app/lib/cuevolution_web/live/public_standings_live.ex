defmodule CuevolutionWeb.PublicStandingsLive do
  @moduledoc """
  The spectator view of the Circuit and the Finals — no account, no controls.

  Two views on the same data: **Live**, the matches being played right now
  with their frame counts, and **Table**, the SP Points ranking. Both update
  themselves. The page subscribes to the `"standings"` topic, which every
  recorded bracket result broadcasts on, so a frame entered by the tournament
  director moves this page on every screen showing it without a reload.

  Deliberately read-only and unauthenticated: the people watching a circuit
  are in the room or following from home, and asking them to sign in to see a
  scoreboard is how a scoreboard goes unused.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias CuevolutionWeb.StandingsRefresh

  @tabs [{"male", "Men"}, {"female", "Ladies"}, {"team", "Teams"}]

  @no_matches %{live: [], next: [], recent: []}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

    {:ok,
     socket
     |> assign(page_title: "Live standings", tabs: @tabs, tab: "male", view: :live)
     |> StandingsRefresh.init()
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["category"] in ~w(male female team), do: params["category"], else: "male"
    view = if params["view"] == "table", do: :table, else: :live

    {:noreply, socket |> assign(tab: tab, view: view) |> load()}
  end

  @impl true
  def handle_event("switch", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: path_for(tab, socket.assigns.view))}
  end

  def handle_event("switch", %{"view" => view}, socket) do
    {:noreply, push_patch(socket, to: path_for(socket.assigns.tab, view))}
  end

  @impl true
  def handle_info({:points_updated, _participant_id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp path_for(tab, view) do
    ~p"/live?#{%{"category" => tab, "view" => to_string(view)}}"
  end

  # Only the view on screen is loaded. This page is public and unauthenticated,
  # so the number of sockets holding these assigns is whoever happens to be
  # watching, and every one of them reloads on every frame scored — loading the
  # standings for a spectator looking at the live matches would double both the
  # memory held and the work done per frame, for nothing anyone can see.
  defp load(socket) do
    category = socket.assigns.tab

    socket
    |> assign(
      live_count: Competitions.live_match_count(category),
      updated_at: Calendar.strftime(Competitions.today_in_eat(), "%-d %b")
    )
    |> load_view(socket.assigns.view, category)
  end

  # The published per-circuit table (SP Points & Standings brief, Nov 2026).
  # The team event is a round robin with no bracket, so it keeps the cumulative
  # table it already had — the brief covers singles only.
  defp load_view(socket, :table, "team" = category) do
    assign(socket,
      rows: Competitions.standings_for_category(category),
      standings_state: :team,
      matches: @no_matches
    )
  end

  defp load_view(socket, :table, category) do
    stage = Competitions.circuit_stage()

    case Competitions.circuit_standings(stage.id, category) do
      nil ->
        assign(socket, rows: [], standings_state: :provisional, matches: @no_matches)

      %{rows: rows, state: state} ->
        assign(socket, rows: rows, standings_state: state, matches: @no_matches)
    end
  end

  defp load_view(socket, :live, category) do
    assign(socket,
      rows: [],
      standings_state: :provisional,
      matches: Competitions.live_matches_for_category(category)
    )
  end

  # ---------------------------------------------------------------- display

  @doc false
  def side_name(nil), do: "—"
  def side_name(%{player: %{first_name: first, last_name: last}}), do: "#{first} #{last}"
  def side_name(%{team: %{name: name}}), do: name
  def side_name(_other), do: "—"

  @doc false
  def side_score(%{result: %{score: %{} = final}}, side), do: Map.get(final, side)
  def side_score(%{live_score: %{} = live}, side), do: Map.get(live, side)
  def side_score(_fixture, _side), do: nil

  @doc false
  def won?(%{result: %{winner_participation_id: id}} = fixture, "a") when is_binary(id),
    do: fixture.participant_a_id == id

  def won?(%{result: %{winner_participation_id: id}} = fixture, "b") when is_binary(id),
    do: fixture.participant_b_id == id

  def won?(_fixture, _side), do: false

  @doc false
  def standings_columns(:team) do
    [
      {"#", "Rank", "text-left"},
      {"Player", "Team", "text-left"},
      {"P", "Matches played", "text-right"},
      {"W", "Matches won", "text-right"},
      {"L", "Matches lost", "text-right"},
      {"SP Points", "SportPesa Points", "text-right"}
    ]
  end

  def standings_columns(state) do
    base = [
      {"Pos", "Position", "text-left"},
      {"Player", "Player", "text-left"},
      {"Region", "Region", "text-left"},
      {"Finish", "Where their circuit ended", "text-left"},
      {"P", "Matches played, byes and walkovers included", "text-right"},
      {"W", "Matches won, byes and walkovers included", "text-right"},
      {"Racks won", "Racks won, byes and walkovers excluded", "text-right"},
      {"Rack-win %", "Racks won / racks played", "text-right"},
      {"SP Points", "SportPesa Points", "text-right"}
    ]

    case state do
      :provisional ->
        {before, rest} = Enum.split(base, 3)
        before ++ [{"Status", "Which side of the bracket they are on", "text-left"}] ++ rest

      _final ->
        base
    end
  end

  @doc false
  def standings_cell(row, "Pos", :team), do: row.rank
  def standings_cell(row, "Pos", state), do: Competitions.position_label(row, state)
  def standings_cell(row, "Player", _state), do: row.name
  def standings_cell(row, "Region", _state), do: row.region
  def standings_cell(row, "Status", _state), do: Competitions.status_label(row)
  def standings_cell(row, "Finish", _state), do: row.finish_label
  def standings_cell(row, "P", _state), do: row.played
  def standings_cell(row, "W", _state), do: row.won
  def standings_cell(row, "L", _state), do: Map.get(row, :lost)
  def standings_cell(row, "Racks won", _state), do: row.racks_won
  def standings_cell(row, "Rack-win %", _state), do: Competitions.rack_win_label(row) || "-"
  def standings_cell(row, "SP Points", :team), do: row.sp_points
  def standings_cell(row, "SP Points", _state), do: row.points

  @doc false
  def signed(value) when value > 0, do: "+#{value}"
  def signed(value), do: to_string(value)

  @doc false
  def start_time(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> nil
      start -> Calendar.strftime(start, "%H:%M")
    end
  end
end
