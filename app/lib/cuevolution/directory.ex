defmodule Cuevolution.Directory do
  @moduledoc """
  Shared filtering for the admin Players/Teams directory — the query logic
  behind `PlayerDirectoryLive` (one paginated page) and
  `AdminDirectoryExportController` (every matching row, for CSV/XLSX),
  factored out so both stay in sync on what a given filter combination
  means.
  """

  alias Cuevolution.Accounts
  alias Cuevolution.Teams

  @doc "Builds the filter map from directory filter-form/query params."
  def build_filters(params) do
    %{}
    |> maybe_put(:region_id, blank_to_nil(params["region_id"]))
    |> maybe_put(:venue_id, blank_to_nil(params["venue_id"]))
    |> maybe_put(:kind, blank_to_nil(params["kind"]))
    |> maybe_put(:stage_id, blank_to_nil(params["stage_id"]))
    |> maybe_put(:search, blank_to_nil(params["search"]))
  end

  @doc """
  Players and teams matching `filters`, honoring `:limit`/`:offset` when
  present (omit both for the export controller's unpaginated fetch).
  """
  def list_players_and_teams(filters) do
    kind = filters[:kind] || "all"

    players =
      if kind in ["all", "male", "female"] do
        Accounts.list_players_filtered(%{
          limit: filters[:limit],
          offset: filters[:offset],
          region_id: filters[:region_id],
          venue_id: filters[:venue_id],
          category: (kind != "all" && kind) || nil,
          username: filters[:search],
          stage_id: filters[:stage_id]
        })
      else
        []
      end

    teams =
      if kind in ["all", "team"] do
        Teams.list_teams_filtered(%{
          limit: filters[:limit],
          offset: filters[:offset],
          region_id: filters[:region_id],
          venue_id: filters[:venue_id],
          name: filters[:search],
          stage_id: filters[:stage_id]
        })
      else
        []
      end

    {players, teams}
  end

  @doc "Total count across players+teams matching `filters`, ignoring pagination."
  def count_players_and_teams(filters) do
    kind = filters[:kind] || "all"

    if(kind in ["all", "male", "female"], do: Accounts.count_players_filtered(filters), else: 0) +
      if kind in ["all", "team"], do: Teams.count_teams_filtered(filters), else: 0
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put(filters, _key, nil), do: filters
  defp maybe_put(filters, key, value), do: Map.put(filters, key, value)
end
