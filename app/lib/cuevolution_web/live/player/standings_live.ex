defmodule CuevolutionWeb.StandingsLive do
  @moduledoc """
  Player standings (spec design: "Standings" screen). `Cuevolution.Competitions`
  doesn't exist yet, so there's no data source at all — every tab is always
  empty, correctly showing the "No standings yet" state. Swap
  `standings_rows/1` for a real query once match results are tracked; the
  region/stage filters are already wired to distinguish "no data at all"
  from "filters narrowed a real result set to zero," ready for that.
  """
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.PlayerComponents
  alias Phoenix.LiveView.JS

  # Mirrors the region set seeded in `regions_seeds.exs` — hardcoded here
  # because standings has no real data yet and thus no FK to `regions`.
  @regions [
    "Nairobi A",
    "Nairobi B",
    "Central",
    "Eastern",
    "Coast",
    "North Rift",
    "South Rift",
    "Nyanza & Western"
  ]

  @stages ~w(Finals Circuit Regional Grassroots)

  @tabs [{"male", "Individual Male"}, {"female", "Individual Female"}, {"team", "Teams"}]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Standings",
       tab: "male",
       region_filter: "All",
       stage_filter: "All",
       tabs: @tabs,
       regions: @regions,
       stages: @stages
     )}
  end

  def render(assigns) do
    all_rows = standings_rows(assigns.tab)

    assigns =
      assign(assigns,
        all_rows: all_rows,
        rows: apply_filters(all_rows, assigns.region_filter, assigns.stage_filter)
      )

    render_standings(assigns)
  end

  embed_templates "standings_live/render_standings*"

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab, region_filter: "All", stage_filter: "All")}
  end

  def handle_event("filter", params, socket) do
    {:noreply,
     assign(socket,
       region_filter: Map.get(params, "region", socket.assigns.region_filter),
       stage_filter: Map.get(params, "stage", socket.assigns.stage_filter)
     )}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign(socket, region_filter: "All", stage_filter: "All")}
  end

  defp apply_filters(rows, region_filter, stage_filter) do
    Enum.filter(rows, fn row ->
      (region_filter == "All" or row.region == region_filter) and
        (stage_filter == "All" or row.stage == stage_filter)
    end)
  end

  # `Cuevolution.Competitions` doesn't exist yet — no match results have
  # ever been recorded, so there's nothing to rank. Replace with a real
  # query once match results are tracked.
  defp standings_rows(_tab), do: []
end
