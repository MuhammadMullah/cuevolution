defmodule CuevolutionWeb.Admin.StandingsLive do
  @moduledoc """
  The singles player standings table for the admin console.

  The per-circuit standings table from the SP Points & Standings brief
  (Nov 2026): Position, Player, Region, Status, Finish, P, W, Racks won, Racks
  played, Rack-win % and SP Points.

  Two views of the same table, and the difference matters:

    * **Provisional**, while the circuit runs — a Status column, and every
      player scored on the stage they have reached so far.
    * **Final**, once the final has been played — players out at the same
      stage share a position (`3=`), the table is marked Final, and it no
      longer changes.

  Ranked on SP Points, then rack-win %, and nothing else. Rack-win % orders
  rows *inside* a shared position for display; it never moves a position or
  changes anyone's points.

  Updates itself as results are entered: it subscribes to the `"standings"`
  topic, which every recorded bracket result broadcasts on.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.StandingsRefresh

  @categories [{"male", "Men's Singles"}, {"female", "Ladies' Singles"}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

    {:ok,
     socket
     |> assign(page_title: "Standings", categories: @categories, category: "male")
     |> StandingsRefresh.init()
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category = if params["category"] in ~w(male female), do: params["category"], else: "male"

    {:noreply, socket |> assign(category: category) |> load()}
  end

  @impl true
  def handle_event("category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/standings?#{%{"category" => category}}")}
  end

  @impl true
  def handle_info({:points_updated, _participant_id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp load(socket) do
    stage = Competitions.circuit_stage()

    case Competitions.circuit_standings(stage.id, socket.assigns.category) do
      nil -> assign(socket, rows: [], state: :provisional)
      %{rows: rows, state: state} -> assign(socket, rows: rows, state: state)
    end
  end

  @doc false
  def columns(:final) do
    [
      {"Pos", "Position", "text-left"},
      {"Player", "Player", "text-left"},
      {"Region", "Region", "text-left"},
      {"Finish", "Where their circuit ended", "text-left"},
      {"P", "Matches played, byes and walkovers included", "text-right"},
      {"W", "Matches won, byes and walkovers included", "text-right"},
      {"Racks won", "Racks won, byes and walkovers excluded", "text-right"},
      {"Racks played", "Racks played, byes and walkovers excluded", "text-right"},
      {"Rack-win %", "Racks won / racks played", "text-right"},
      {"SP Points", "SportPesa Points", "text-right"}
    ]
  end

  def columns(:provisional) do
    {before, rest} = Enum.split(columns(:final), 3)
    before ++ [{"Status", "Which side of the bracket they are on", "text-left"}] ++ rest
  end

  @doc false
  def cell(row, "Pos", state), do: Competitions.position_label(row, state)
  def cell(row, "Player", _state), do: row.name
  def cell(row, "Region", _state), do: row.region
  def cell(row, "Status", _state), do: Competitions.status_label(row)
  def cell(row, "Finish", _state), do: row.finish_label
  def cell(row, "P", _state), do: row.played
  def cell(row, "W", _state), do: row.won
  def cell(row, "Racks won", _state), do: row.racks_won
  def cell(row, "Racks played", _state), do: row.racks_played
  def cell(row, "Rack-win %", _state), do: Competitions.rack_win_label(row) || "-"
  def cell(row, "SP Points", _state), do: row.points
end
