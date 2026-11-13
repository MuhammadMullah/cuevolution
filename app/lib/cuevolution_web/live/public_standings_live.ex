defmodule CuevolutionWeb.PublicStandingsLive do
  @moduledoc """
  The spectator view of the Circuit and the Finals — no account, no controls.

  Two views on the same data: **Live**, the matches being played right now
  with their frame counts, and **Table**, the SP Points ranking. On the Teams
  tab the table comes in two scopes — **Overall**, every team in one ranking,
  and **Groups**, the two Circuit round-robin groups with the qualification
  line marked. Both update themselves. The page subscribes to the `"standings"` topic, which every
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
     |> assign(
       page_title: "Live standings",
       tabs: @tabs,
       tab: "male",
       view: :live,
       scope: :overall
     )
     |> StandingsRefresh.init()
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["category"] in ~w(male female team), do: params["category"], else: "male"
    view = if params["view"] == "table", do: :table, else: :live
    scope = if params["scope"] == "groups", do: :groups, else: :overall

    {:noreply, socket |> assign(tab: tab, view: view, scope: scope) |> load()}
  end

  @impl true
  def handle_event("switch", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: path_for(tab, socket.assigns.view, socket.assigns.scope))}
  end

  def handle_event("switch", %{"view" => view}, socket) do
    {:noreply, push_patch(socket, to: path_for(socket.assigns.tab, view, socket.assigns.scope))}
  end

  def handle_event("switch", %{"scope" => scope}, socket) do
    {:noreply, push_patch(socket, to: path_for(socket.assigns.tab, socket.assigns.view, scope))}
  end

  @impl true
  def handle_info({:points_updated, _participant_id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp path_for(tab, view, scope) do
    params = %{"category" => tab, "view" => to_string(view)}

    params =
      if tab == "team" and to_string(scope) == "groups",
        do: Map.put(params, "scope", "groups"),
        else: params

    ~p"/live?#{params}"
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

  # The team event is a round robin with no bracket, so it keeps the cumulative
  # table it already had — the per-circuit brief covers singles only. Its two
  # groups are the other half of the story: the cumulative table says who is
  # best, the group tables say who is qualifying, and a captain wants the
  # second one.
  defp load_view(socket, :table, "team" = category) do
    socket
    |> assign(matches: @no_matches)
    |> load_team_table(socket.assigns.scope, category)
  end

  # The published per-circuit table (SP Points & Standings brief, Nov 2026).
  defp load_view(socket, :table, category) do
    stage = Competitions.circuit_stage()

    case Competitions.circuit_standings(stage.id, category) do
      nil ->
        socket |> assign_table([], :provisional) |> assign(matches: @no_matches)

      %{rows: rows, state: state} ->
        socket |> assign_table([section(rows)], state) |> assign(matches: @no_matches)
    end
  end

  defp load_view(socket, :live, category) do
    socket
    |> assign_table([], :provisional)
    |> assign(matches: Competitions.live_matches_for_category(category))
  end

  defp load_team_table(socket, :groups, _category) do
    sections =
      Competitions.circuit_team_standings(Competitions.circuit_stage().id)
      |> Enum.map(fn %{group: group, rows: rows, advancer_count: advancers} ->
        rows
        |> Enum.map(&Map.delete(&1, :participation))
        |> section(group.name, "Top #{advancers} to the Nationals")
      end)

    assign_table(socket, sections, :team_group)
  end

  defp load_team_table(socket, _overall, category) do
    assign_table(socket, [section(Competitions.standings_for_category(category))], :team)
  end

  defp section(rows, title \\ nil, note \\ nil), do: %{title: title, note: note, rows: rows}

  # `has_rows?` rather than the template asking whether every section is empty:
  # a drawn-but-unplayed team event has two sections full of teams on zero, and
  # a table of zeroes is the right thing to show, not an empty state.
  defp assign_table(socket, sections, state) do
    assign(socket,
      sections: sections,
      standings_state: state,
      has_rows?: Enum.any?(sections, &(&1.rows != []))
    )
  end

  # ---------------------------------------------------------------- display

  @doc false
  def side_name(nil), do: "—"

  def side_name(%{player: %{first_name: first, last_name: last}}),
    do: Names.full_name(first, last)

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
      {"Pos", "Position", "text-left"},
      {"Team", "Team", "text-left"},
      {"MP", "Matches played", "text-right"},
      {"MW", "Matches won", "text-right"},
      {"ML", "Matches lost", "text-right"},
      {"Win %", "Matches won / matches played", "text-right"},
      {"FP", "Frames played", "text-right"},
      {"FW", "Frames won", "text-right"},
      {"FL", "Frames lost", "text-right"},
      {"Frame Win %", "Frames won / frames played", "text-right"},
      {"SP Points", "SportPesa Points", "text-right"}
    ]
  end

  def standings_columns(:team_group) do
    [{"Pos", _title, align} | rest] = standings_columns(:team)
    {record, [sp_points]} = Enum.split(rest, -1)

    [{"Pos", "Position in the group", align}] ++
      record ++ [{"FD", "Frame difference", "text-right"}, sp_points]
  end

  def standings_columns(state) do
    base = [
      {"Pos", "Position", "text-left"},
      {"Player", "Player", "text-left"},
      {"Region", "Region", "text-left"},
      {"Finish", "Where their circuit ended", "text-left"},
      {"MP", "Matches played, byes and walkovers included", "text-right"},
      {"MW", "Matches won, byes and walkovers included", "text-right"},
      {"ML", "Matches lost, byes and walkovers included", "text-right"},
      {"Win %", "Matches won / matches played", "text-right"},
      {"FP", "Frames (racks) played, byes and walkovers excluded", "text-right"},
      {"FW", "Frames (racks) won, byes and walkovers excluded", "text-right"},
      {"FL", "Frames (racks) lost, byes and walkovers excluded", "text-right"},
      {"Frame Win %", "Frames won / frames played", "text-right"},
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
  def standings_cell(%{tied: true} = row, "Pos", :team_group), do: "#{row.rank}="
  def standings_cell(row, "Pos", state) when state in [:team, :team_group], do: row.rank
  def standings_cell(row, "Pos", state), do: Competitions.position_label(row, state)
  def standings_cell(row, "Player", _state), do: row.name
  def standings_cell(row, "Team", _state), do: row.name
  def standings_cell(row, "Region", _state), do: row.region
  def standings_cell(row, "Status", _state), do: Competitions.status_label(row)
  def standings_cell(row, "Finish", _state), do: row.finish_label
  def standings_cell(row, "MP", :team_group), do: row.matches_played
  def standings_cell(row, "MP", _state), do: row.played
  def standings_cell(row, "MW", :team_group), do: row.wins
  def standings_cell(row, "MW", _state), do: row.won
  def standings_cell(row, "ML", :team_group), do: row.losses
  def standings_cell(row, "ML", _state), do: row.lost
  def standings_cell(row, "Win %", _state), do: Competitions.pct_label(row.win_pct) || "-"

  def standings_cell(row, "FP", state) when state in [:team, :team_group],
    do: row.frames_played

  def standings_cell(row, "FP", _state), do: row.racks_played

  def standings_cell(row, "FW", state) when state in [:team, :team_group], do: row.frames_won
  def standings_cell(row, "FW", _state), do: row.racks_won
  def standings_cell(row, "FL", state) when state in [:team, :team_group], do: row.frames_lost
  def standings_cell(row, "FL", _state), do: row.racks_lost

  def standings_cell(row, "Frame Win %", state) when state in [:team, :team_group],
    do: Competitions.pct_label(row.frame_win_pct) || "-"

  def standings_cell(row, "Frame Win %", _state),
    do: Competitions.pct_label(row.rack_win_pct) || "-"

  def standings_cell(row, "FD", :team_group), do: signed(row.frame_diff)

  def standings_cell(row, "SP Points", state) when state in [:team, :team_group],
    do: row.sp_points

  def standings_cell(row, "SP Points", _state), do: row.points

  @doc false
  def scopes, do: [{"Overall", :overall}, {"Groups", :groups}]

  @doc false
  def empty_message(:team_group), do: "The team groups have not been drawn yet."
  def empty_message(_state), do: "No standings yet for this category."

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
