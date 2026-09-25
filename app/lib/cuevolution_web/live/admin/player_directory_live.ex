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
  alias Cuevolution.Directory
  alias Cuevolution.Venues
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
    filters = Directory.build_filters(params)
    page = page_number(params["page"])

    {:ok,
     socket
     |> assign(
       page_title: "Directory",
       regions: Accounts.list_regions(),
       stages: Competitions.list_stages(),
       kinds: @kinds,
       filter_form: to_form(params, as: :filter),
       filters: filters,
       venues: list_venues(filters[:region_id]),
       page: page
     )
     |> assign_directory(filters, page)}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    filters = Directory.build_filters(params)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(params, as: :filter))
     |> assign(:filters, filters)
     |> assign(:venues, list_venues(filters[:region_id]))
     |> assign(:page, 1)
     |> assign_directory(filters, 1)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = page_number(page)
    filters = socket.assigns.filters

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign_directory(filters, page)}
  end

  defp list_venues(nil), do: Venues.list_venues(%{})
  defp list_venues(region_id), do: Venues.list_venues(%{region_id: region_id})

  defp assign_directory(socket, filters, page) do
    {rows, total_count} = build_rows(filters, page)

    assign(socket,
      rows: rows,
      total_count: total_count,
      total_pages: max(1, ceil(total_count / @page_size))
    )
  end

  defp build_rows(filters, page) do
    query_filters =
      Map.merge(filters, %{limit: @page_size, offset: (page - 1) * @page_size})

    {players, teams} = Directory.list_players_and_teams(query_filters)
    total_count = Directory.count_players_and_teams(filters)

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

  # Venue options are already region-scoped once a region filter is chosen,
  # so the region name would be redundant there — it only earns its place
  # in the "All regions" list, where several venues can share a name.
  defp venue_option_label(venue, nil), do: "#{venue.name} (#{venue.region.name})"
  defp venue_option_label(venue, _region_id), do: venue.name

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
