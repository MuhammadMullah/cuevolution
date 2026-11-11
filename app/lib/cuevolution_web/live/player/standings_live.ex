defmodule CuevolutionWeb.StandingsLive do
  @moduledoc """
  Player standings (spec 009) — live-ranked by Cuevo Points, subscribes to
  the `"standings"` PubSub topic (first real PubSub usage in this app,
  wired in `Competitions.record_points/3`/`correct_points/3`) so a points
  change from any admin session re-ranks every connected viewer without a
  page reload.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias CuevolutionWeb.PlayerComponents
  alias CuevolutionWeb.StandingsRefresh
  alias Phoenix.LiveView.JS

  @tabs [{"male", "Individual Male"}, {"female", "Individual Female"}, {"team", "Teams"}]

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

    {:ok,
     socket
     |> assign(
       page_title: "Standings",
       tab: "male",
       region_filter: "All",
       stage_filter: "All",
       tabs: @tabs,
       regions: Enum.map(Accounts.list_regions(), & &1.name),
       stages: ["Circuit", "Finals"]
     )
     |> StandingsRefresh.init()
     |> load_standings()}
  end

  embed_templates "standings_live/render_standings*"

  def render(assigns), do: render_standings(assigns)

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(tab: tab, region_filter: "All", stage_filter: "All")
     |> load_standings()}
  end

  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(
       region_filter: Map.get(params, "region", socket.assigns.region_filter),
       stage_filter: Map.get(params, "stage", socket.assigns.stage_filter)
     )
     |> load_standings()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(region_filter: "All", stage_filter: "All")
     |> load_standings()}
  end

  # Coalesced: a busy circuit broadcasts on every frame, and this page is one
  # socket per signed-in player.
  def handle_info({:points_updated, _participant_id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load_standings/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load_standings/1)}
  end

  defp load_standings(socket) do
    all_rows = Competitions.standings_for_category(socket.assigns.tab)
    rows = apply_filters(all_rows, socket.assigns.region_filter, socket.assigns.stage_filter)

    socket
    |> assign(all_rows_empty?: all_rows == [], rows_empty?: rows == [])
    |> stream(:standings, rows, reset: true)
  end

  defp apply_filters(rows, region_filter, stage_filter) do
    Enum.filter(rows, fn row ->
      (region_filter == "All" or row.region == region_filter) and
        (stage_filter == "All" or row.stage == stage_filter)
    end)
  end

  # ------------------------------------------------------------- the record

  # The match record then the frame record, in table order. The header and the
  # cells both read this one list, so neither can go missing from the other.
  @metric_columns [
    {"MP", "Matches played"},
    {"MW", "Matches won"},
    {"ML", "Matches lost"},
    {"Win %", "Matches won / matches played"},
    {"FP", "Frames played"},
    {"FW", "Frames won"},
    {"FL", "Frames lost"},
    {"Frame Win %", "Frames won / frames played"}
  ]

  @doc false
  def metric_columns, do: @metric_columns

  @doc false
  def metrics(row),
    do: Enum.map(@metric_columns, fn {label, _} -> {label, metric(row, label)} end)

  defp metric(row, "MP"), do: row.played
  defp metric(row, "MW"), do: row.won
  defp metric(row, "ML"), do: row.lost
  defp metric(row, "Win %"), do: Competitions.pct_label(row.win_pct) || "—"
  defp metric(row, "FP"), do: row.frames_played
  defp metric(row, "FW"), do: row.frames_won
  defp metric(row, "FL"), do: row.frames_lost
  defp metric(row, "Frame Win %"), do: Competitions.pct_label(row.frame_win_pct) || "—"
end
