defmodule CuevolutionWeb.PlayerDirectoryLive do
  @moduledoc """
  Admin "Directory" (project-scope/Quevolution/Cuevolution Admin.dc.html) —
  one unified, filterable list of Players and Teams, with a Stage filter
  and per-row stage badge sourced from `Competitions.StageParticipation`.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Competitions
  alias Cuevolution.Teams
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  @kinds [
    {"All", "all"},
    {"Individual Male", "male"},
    {"Individual Female", "female"},
    {"Teams", "team"}
  ]
  @page_size 50

  def mount(params, _session, socket) do
    filters = build_filters(params)
    page = page_number(params["page"])

    {:ok,
     socket
     |> assign(
       page_title: "Directory",
       regions: Accounts.list_regions(),
       stages: Competitions.list_stages(),
       kinds: @kinds,
       filter_form: to_form(params, as: :filter),
       page: page
     )
     |> assign_directory(filters, page)}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    filters = build_filters(params)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(params, as: :filter))
     |> assign(:page, 1)
     |> assign_directory(filters, 1)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = page_number(page)
    filters = build_filters(socket.assigns.filter_form.params)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign_directory(filters, page)}
  end

  defp build_filters(params) do
    %{}
    |> maybe_put_filter(:region_id, blank_to_nil(params["region_id"]))
    |> maybe_put_filter(:kind, blank_to_nil(params["kind"]))
    |> maybe_put_filter(:stage_id, blank_to_nil(params["stage_id"]))
    |> maybe_put_filter(:search, blank_to_nil(params["search"]))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put_filter(filters, _key, nil), do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  defp assign_directory(socket, filters, page) do
    {rows, total_count} = build_rows(filters, page)

    assign(socket,
      rows: rows,
      total_count: total_count,
      total_pages: max(1, ceil(total_count / @page_size))
    )
  end

  defp build_rows(filters, page) do
    kind = filters[:kind] || "all"
    stage_id = filters[:stage_id]
    query_filters = Map.merge(filters, %{limit: @page_size, offset: (page - 1) * @page_size})

    players =
      if kind in ["all", "male", "female"] do
        Accounts.list_players_filtered(%{
          limit: query_filters.limit,
          offset: query_filters.offset,
          region_id: filters[:region_id],
          category: (kind != "all" && kind) || nil,
          username: filters[:search],
          stage_id: stage_id
        })
      else
        []
      end

    teams =
      if kind in ["all", "team"] do
        Teams.list_teams_filtered(%{
          limit: query_filters.limit,
          offset: query_filters.offset,
          region_id: filters[:region_id],
          name: filters[:search],
          stage_id: stage_id
        })
      else
        []
      end

    total_count =
      if(kind in ["all", "male", "female"],
        do: Accounts.count_players_filtered(filters),
        else: 0
      ) +
        if kind in ["all", "team"], do: Teams.count_teams_filtered(filters), else: 0

    stage_lookup =
      Competitions.stages_by_participant(Enum.map(players, & &1.id), Enum.map(teams, & &1.id))

    (Enum.map(players, &player_row(&1, stage_lookup)) ++
       Enum.map(teams, &team_row(&1, stage_lookup)))
    |> Enum.sort_by(&String.downcase(&1.name))
    |> then(&{&1, total_count})
  end

  defp page_number(page) when is_integer(page) and page > 0, do: page

  defp page_number(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page_number(_page), do: 1

  defp player_row(player, stage_lookup) do
    %{
      id: player.id,
      kind: :player,
      name: "#{player.first_name} #{player.last_name}",
      avatar_name: "#{player.first_name} #{player.last_name}",
      avatar_src: ProfilePicture.url(player.profile_picture_path),
      sub: "Player · #{player.region.name} · @#{player.username}",
      stage: Map.get(stage_lookup, player.id),
      anonymized: !is_nil(player.anonymized_at),
      path: ~p"/admin/players/#{player.id}"
    }
  end

  defp team_row(team, stage_lookup) do
    %{
      id: team.id,
      kind: :team,
      name: team.name,
      avatar_name: team.name,
      avatar_src: nil,
      sub: "Team · #{team.region.name} · #{length(team.roster)} on roster",
      stage: Map.get(stage_lookup, team.id),
      anonymized: false,
      path: ~p"/admin/teams/#{team.id}"
    }
  end
end
