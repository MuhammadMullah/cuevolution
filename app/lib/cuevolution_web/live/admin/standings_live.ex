defmodule CuevolutionWeb.Admin.StandingsLive do
  @moduledoc """
  The singles player standings table for the admin console.

  Ten columns per the committee brief — rank, player, MP, MW, ML, MD, FW, FL,
  FD and SP Points — for Men's and Ladies' Singles separately.

  **SP Points always decide the ranking.** The other statistics only separate
  players level on points, in the published order: match difference, then
  frame difference, then frames won (`Competitions.standings_for_category/1`).
  The column headers are sortable for looking the table over, but sorting by
  another column never changes a player's rank — the rank is the standing, and
  it travels with the row.

  Updates itself as results are entered: it subscribes to the `"standings"`
  topic, which every recorded bracket result broadcasts on.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.StandingsRefresh

  @categories [{"male", "Men's Singles"}, {"female", "Ladies' Singles"}]

  @sortable ~w(rank name played won lost match_difference frames_won frames_lost
               frame_difference sp_points)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

    {:ok,
     socket
     |> assign(
       page_title: "Standings",
       categories: @categories,
       category: "male",
       sort_by: "rank",
       sort_dir: :asc
     )
     |> StandingsRefresh.init()
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category = if params["category"] in ~w(male female), do: params["category"], else: "male"
    sort_by = if params["sort"] in @sortable, do: params["sort"], else: "rank"
    sort_dir = if params["dir"] == "desc", do: :desc, else: :asc

    {:noreply,
     socket
     |> assign(category: category, sort_by: sort_by, sort_dir: sort_dir)
     |> load()}
  end

  @impl true
  def handle_event("category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: path_for(category, "rank", :asc))}
  end

  def handle_event("sort", %{"by" => by}, socket) when by in @sortable do
    # Clicking the active column flips it; a new column starts in the
    # direction that is useful for it — descending for a tally, ascending for
    # a rank or a name.
    dir =
      cond do
        socket.assigns.sort_by != by and by in ~w(rank name) -> :asc
        socket.assigns.sort_by != by -> :desc
        socket.assigns.sort_dir == :asc -> :desc
        true -> :asc
      end

    {:noreply, push_patch(socket, to: path_for(socket.assigns.category, by, dir))}
  end

  @impl true
  def handle_info({:points_updated, _participant_id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp path_for(category, sort, dir) do
    ~p"/admin/standings?#{%{"category" => category, "sort" => sort, "dir" => dir}}"
  end

  defp load(socket) do
    rows =
      socket.assigns.category
      |> Competitions.standings_for_category()
      |> sort_rows(socket.assigns.sort_by, socket.assigns.sort_dir)

    assign(socket, rows: rows)
  end

  # Sorting is a view over the table, never a re-ranking: `rank` is already on
  # each row from the published order and is not recomputed here.
  defp sort_rows(rows, "name", dir), do: Enum.sort_by(rows, & &1.name, dir)

  defp sort_rows(rows, column, dir) do
    key = String.to_existing_atom(column)
    Enum.sort_by(rows, &{Map.fetch!(&1, key), &1.name}, dir)
  end

  @doc false
  def columns do
    [
      {"rank", "#", "Rank", "text-left"},
      {"name", "Player", "Player name", "text-left"},
      {"played", "MP", "Matches played", "text-right"},
      {"won", "MW", "Matches won", "text-right"},
      {"lost", "ML", "Matches lost", "text-right"},
      {"match_difference", "MD", "Match difference (MW − ML)", "text-right"},
      {"frames_won", "FW", "Frames won", "text-right"},
      {"frames_lost", "FL", "Frames lost", "text-right"},
      {"frame_difference", "FD", "Frame difference (FW − FL)", "text-right"},
      {"sp_points", "SP Points", "SportPesa Points", "text-right"}
    ]
  end

  @doc false
  def cell(row, "rank"), do: row.rank
  def cell(row, "name"), do: row.name
  def cell(row, "played"), do: row.played
  def cell(row, "won"), do: row.won
  def cell(row, "lost"), do: row.lost
  def cell(row, "match_difference"), do: signed(row.match_difference)
  def cell(row, "frames_won"), do: row.frames_won
  def cell(row, "frames_lost"), do: row.frames_lost
  def cell(row, "frame_difference"), do: signed(row.frame_difference)
  def cell(row, "sp_points"), do: row.sp_points

  defp signed(value) when value > 0, do: "+#{value}"
  defp signed(value), do: to_string(value)
end
