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
    case filters[:limit] do
      nil -> {players(filters, %{}), teams(filters, %{})}
      limit -> page(filters, limit, filters[:offset] || 0)
    end
  end

  @doc "Total count across players+teams matching `filters`, ignoring pagination."
  def count_players_and_teams(filters) do
    player_count(filters) + team_count(filters)
  end

  # Players and teams are two queries behind a single paginated list, so a
  # page has to be *split* across them. Handing both the same LIMIT/OFFSET
  # made page 1 up to twice `limit` rows long and left as many trailing
  # pages empty, since the pager sizes itself on the combined count.
  defp page(filters, limit, offset) do
    available = player_count(filters)

    players =
      if offset < available, do: players(filters, %{limit: limit, offset: offset}), else: []

    taken = length(players)

    teams =
      cond do
        taken >= limit -> []
        taken > 0 -> teams(filters, %{limit: limit - taken, offset: 0})
        true -> teams(filters, %{limit: limit, offset: offset - available})
      end

    {players, teams}
  end

  defp players(filters, pagination) do
    if players?(filters),
      do: Accounts.list_players_filtered(Map.merge(player_filters(filters), pagination)),
      else: []
  end

  defp teams(filters, pagination) do
    if teams?(filters),
      do: Teams.list_teams_filtered(Map.merge(team_filters(filters), pagination)),
      else: []
  end

  defp player_count(filters) do
    if players?(filters), do: Accounts.count_players_filtered(player_filters(filters)), else: 0
  end

  defp team_count(filters) do
    if teams?(filters), do: Teams.count_teams_filtered(team_filters(filters)), else: 0
  end

  # The listing and the count have to translate the directory's filter names
  # into each context's own filter names identically, or the page reports a
  # total that its own rows contradict — the count used to be handed the raw
  # directory filters, silently ignoring `:kind`/`:search` because the
  # contexts look for `:category`/`:search` instead, so a search that matched
  # nothing still advertised every player in the system.
  defp player_filters(filters) do
    %{
      region_id: filters[:region_id],
      venue_id: filters[:venue_id],
      category: category(filters),
      search: filters[:search],
      stage_id: filters[:stage_id]
    }
  end

  defp team_filters(filters) do
    %{
      region_id: filters[:region_id],
      venue_id: filters[:venue_id],
      name: filters[:search],
      stage_id: filters[:stage_id]
    }
  end

  defp kind(filters), do: filters[:kind] || "all"

  defp players?(filters), do: kind(filters) in ["all", "male", "female"]
  defp teams?(filters), do: kind(filters) in ["all", "team"]

  # "all" is the absence of a gender filter, not a gender.
  defp category(filters) do
    case kind(filters) do
      "all" -> nil
      gender -> gender
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put(filters, _key, nil), do: filters
  defp maybe_put(filters, key, value), do: Map.put(filters, key, value)
end
