defmodule CuevolutionWeb.PlayerDirectoryLive do
  @moduledoc """
  Admin "Directory" (project-scope/Quevolution/Cuevolution Admin.dc.html) —
  one unified, filterable list of Players and Teams, with a Stage filter
  and per-row stage badge sourced from `Competitions.StageParticipation`.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
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

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Directory",
       regions: Accounts.list_regions(),
       stages: Competitions.list_stages(),
       kinds: @kinds,
       filter_form: to_form(%{}, as: :filter)
     )
     |> assign(:rows, build_rows(%{}))}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    filters = build_filters(params)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(params, as: :filter))
     |> assign(:rows, build_rows(filters))}
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

  defp build_rows(filters) do
    kind = filters[:kind] || "all"
    stage_lookup = stage_lookup()

    players =
      if kind in ["all", "male", "female"] do
        Accounts.list_players_filtered(%{
          region_id: filters[:region_id],
          category: (kind != "all" && kind) || nil,
          username: filters[:search]
        })
        |> Enum.filter(&matches_stage?(&1.id, filters[:stage_id], stage_lookup))
      else
        []
      end

    teams =
      if kind in ["all", "team"] do
        Teams.list_teams_filtered(%{region_id: filters[:region_id], name: filters[:search]})
        |> Enum.filter(&matches_stage?(&1.id, filters[:stage_id], stage_lookup))
      else
        []
      end

    (Enum.map(players, &player_row(&1, stage_lookup)) ++
       Enum.map(teams, &team_row(&1, stage_lookup)))
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp stage_lookup do
    Competitions.list_participations()
    |> Map.new(&{&1.player_id || &1.team_id, &1.stage})
  end

  defp matches_stage?(_id, nil, _lookup), do: true

  defp matches_stage?(id, stage_id, lookup) do
    case Map.get(lookup, id) do
      nil -> false
      stage -> stage.id == stage_id
    end
  end

  defp player_row(player, stage_lookup) do
    %{
      id: player.id,
      kind: :player,
      name: "#{player.first_name} #{player.last_name}",
      avatar_name: "#{player.first_name} #{player.last_name}",
      avatar_src: player.profile_picture_path,
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
