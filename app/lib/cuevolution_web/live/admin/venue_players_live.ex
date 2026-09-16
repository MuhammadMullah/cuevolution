defmodule CuevolutionWeb.VenuePlayersLive do
  @moduledoc """
  Admin "Venue players" page (project-scope/Quevolution/Cuevolution
  Admin.dc.html) — opened by clicking a venue in the dashboard's "Players
  per venue" chart, not part of the nav. A directory of players scoped to
  one venue, with its own search/kind filter and pagination.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Competitions
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  @show_step 25

  @kinds [
    {"All", "all"},
    {"Male", "male"},
    {"Female", "female"},
    {"Teams", "team"}
  ]

  def mount(%{"id" => venue_id}, _session, socket) do
    venue = Venues.get_venue!(venue_id)

    {:ok,
     socket
     |> assign(
       page_title: venue.name,
       venue: venue,
       kinds: @kinds,
       tiles: venue_tiles(venue.id),
       search: "",
       kind: "all",
       show: @show_step,
       modal_player: nil,
       modal_stage: nil,
       modal_notifications: [],
       anonymize_warnings: nil
     )
     |> assign_filter_form()
     |> assign_rows()}
  end

  def handle_event("open_player", %{"id" => id}, socket) do
    player = Player |> Repo.get!(id) |> Repo.preload(:region)
    stage = Competitions.stages_by_participant([id], []) |> Map.get(id)

    notifications =
      Notification
      |> where(player_id: ^id)
      |> order_by(desc: :inserted_at)
      |> limit(10)
      |> Repo.all()

    {:noreply,
     assign(socket,
       modal_player: player,
       modal_stage: stage,
       modal_notifications: notifications,
       anonymize_warnings: nil
     )}
  end

  def handle_event("close_player_modal", _params, socket) do
    {:noreply,
     assign(socket,
       modal_player: nil,
       modal_stage: nil,
       modal_notifications: [],
       anonymize_warnings: nil
     )}
  end

  def handle_event("confirm_anonymize", _params, socket) do
    if Admin.can?(socket.assigns.current_admin, :anonymize_users) do
      {:noreply,
       assign(
         socket,
         :anonymize_warnings,
         Accounts.anonymize_warnings(socket.assigns.modal_player)
       )}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to anonymize users.")}
    end
  end

  def handle_event("cancel_anonymize", _params, socket) do
    {:noreply, assign(socket, :anonymize_warnings, nil)}
  end

  def handle_event("anonymize", _params, socket) do
    case Accounts.anonymize_player(socket.assigns.modal_player, socket.assigns.current_admin) do
      {:ok, _player} ->
        {:noreply,
         socket
         |> assign(
           modal_player: nil,
           modal_stage: nil,
           modal_notifications: [],
           anonymize_warnings: nil
         )
         |> assign(:tiles, venue_tiles(socket.assigns.venue.id))
         |> assign_rows()
         |> put_flash(:info, "Player anonymized.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to anonymize users.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't anonymize this player.")}
    end
  end

  def handle_event("filter", %{"venue_players_filter" => %{"q" => search}}, socket) do
    {:noreply,
     socket |> assign(search: search, show: @show_step) |> assign_filter_form() |> assign_rows()}
  end

  def handle_event("set_kind", %{"kind" => kind}, socket) do
    {:noreply,
     socket |> assign(kind: kind, show: @show_step) |> assign_filter_form() |> assign_rows()}
  end

  def handle_event("show_more", _params, socket) do
    {:noreply, socket |> assign(show: socket.assigns.show + @show_step) |> assign_rows()}
  end

  defp assign_filter_form(socket) do
    assign(socket,
      filter_form: to_form(%{"q" => socket.assigns.search}, as: :venue_players_filter)
    )
  end

  defp assign_rows(socket) do
    %{venue: venue, kind: kind, search: search, show: show} = socket.assigns

    players =
      venue.id
      |> venue_players_query(kind, search)
      |> Repo.all()

    total_matched = length(players)
    shown = Enum.take(players, show)

    stage_lookup =
      Competitions.stages_by_participant(Enum.map(shown, & &1.id), [])

    rows = Enum.map(shown, &player_row(&1, stage_lookup))
    remaining = total_matched - length(rows)

    assign(socket,
      rows: rows,
      total_matched: total_matched,
      count_label: "Showing #{length(rows)} of #{total_matched} players",
      has_more: remaining > 0,
      more_label: "Show #{min(@show_step, remaining)} more"
    )
  end

  defp venue_players_query(venue_id, kind, search) do
    venue_id
    |> Accounts.list_players_by_preferred_venue()
    |> filter_by_kind(kind)
    |> filter_by_search(search)
    |> order_by(asc: :username)
    |> preload(:team)
  end

  defp filter_by_kind(query, "male"),
    do: where(query, [p], p.gender == "male" and is_nil(p.team_id))

  defp filter_by_kind(query, "female"),
    do: where(query, [p], p.gender == "female" and is_nil(p.team_id))

  defp filter_by_kind(query, "team"), do: where(query, [p], not is_nil(p.team_id))
  defp filter_by_kind(query, _all), do: query

  defp filter_by_search(query, search) when search in [nil, ""], do: query

  defp filter_by_search(query, search) do
    pattern = "%" <> escape_like_pattern(search) <> "%"

    where(
      query,
      [p],
      ilike(fragment("? || ' ' || ?", p.first_name, p.last_name), ^pattern) or
        ilike(p.username, ^pattern)
    )
  end

  defp escape_like_pattern(value), do: String.replace(value, ~w(% _), fn c -> "\\" <> c end)

  defp player_row(player, stage_lookup) do
    %{
      id: player.id,
      name: "#{player.first_name} #{player.last_name}",
      avatar_name: "#{player.first_name} #{player.last_name}",
      avatar_src: ProfilePicture.url(player.profile_picture_path),
      sub: "@#{player.username} · #{kind_label(player)}",
      stage: Map.get(stage_lookup, player.id)
    }
  end

  defp kind_label(%{team: %{name: name}}), do: name
  defp kind_label(%{gender: "male"}), do: "Individual male"
  defp kind_label(%{gender: "female"}), do: "Individual female"

  defp player_fields(player, stage) do
    [
      {"Username", "@#{player.username}"},
      {"Region", player.region.name},
      {"Location", player.location},
      {"Email", player.email},
      {"Mobile", player.mobile_number},
      {"Stage", (stage && stage.name) || "Not yet assigned"}
    ]
  end

  defp venue_tiles(venue_id) do
    base = Accounts.list_players_by_preferred_venue(venue_id)

    total = Repo.aggregate(base, :count)

    male =
      Repo.aggregate(from(p in base, where: p.gender == "male" and is_nil(p.team_id)), :count)

    female =
      Repo.aggregate(from(p in base, where: p.gender == "female" and is_nil(p.team_id)), :count)

    teams = Repo.aggregate(from(p in base, where: not is_nil(p.team_id)), :count)

    [
      %{label: "Registered players", value: total},
      %{label: "Individual male", value: male},
      %{label: "Individual female", value: female},
      %{label: "Teams", value: teams}
    ]
  end
end
