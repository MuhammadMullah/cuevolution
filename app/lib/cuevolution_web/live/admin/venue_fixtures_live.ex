defmodule CuevolutionWeb.VenueFixturesLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    admin = Repo.preload(socket.assigns.current_admin, [:venue, :region])

    {venue, region_venues} =
      case admin.role do
        "regional_coordinator" ->
          venues =
            if admin.region_id, do: Venues.list_active_for_region(admin.region_id), else: []

          {nil, venues}

        "venue_representative" ->
          {admin.venue, []}

        _ ->
          {nil, []}
      end

    socket =
      assign(socket,
        page_title: "Venue Fixtures",
        current_admin: admin,
        venue: venue,
        region: admin.region,
        region_venues: region_venues,
        venue_filter_id: scope_venue_filter_id(admin, nil),
        available_groups: [],
        group_filter: "",
        player_search: "",
        page: 1,
        total_pages: 1,
        total_fixtures_count: 0,
        page_fixtures: []
      )

    # Deferred past the disconnected (HTTP) render so a visit to this page
    # doesn't query twice per visit — once disconnected, once again right
    # after the socket connects.
    socket =
      if connected?(socket),
        do: socket |> load_available_groups() |> load_fixtures(),
        else: socket

    {:ok, socket}
  end

  def handle_event("filter_venue", params, socket), do: apply_filters(params, socket)
  def handle_event("filter_fixtures", params, socket), do: apply_filters(params, socket)

  def handle_event("clear_filters", _params, socket) do
    apply_filters(%{"venue_id" => "", "group_name" => "", "player_search" => ""}, socket)
  end

  def handle_event("change_page", %{"page" => page}, socket) do
    page = parse_page(page, socket.assigns.total_pages)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_fixtures()}
  end

  def render(assigns) do
    ~H"""
    <AdminComponents.app_shell current_admin={@current_admin} active={:venue_fixtures} flash={@flash}>
      <AdminComponents.eyebrow class="mb-1.5">Venue coordination</AdminComponents.eyebrow>
      <div class="mb-5 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 class="text-[clamp(24px,4vw,30px)] font-bold tracking-tight text-ink-950">
            Venue fixtures
          </h1>
          <p :if={@venue} class="mt-1 text-sm text-ink-500">{@venue.name} · all groups</p>
          <p
            :if={@current_admin.role == "regional_coordinator" && @region}
            class="mt-1 text-sm text-ink-500"
          >
            {@region.name} · all venues
          </p>
        </div>
        <div class="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center">
          <span :if={@total_fixtures_count > 0} class="font-mono text-xs text-ink-500">
            {@total_fixtures_count} fixtures
          </span>
          <a
            :if={@venue || @region}
            href={download_path(@venue_filter_id)}
            download
            class="inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 transition hover:border-ink-950 hover:text-ink-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink-950"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download PDF
          </a>
        </div>
      </div>

      <form
        :if={(@current_admin.role == "regional_coordinator" && @region) || @venue}
        id="venue-filter-form"
        phx-change="filter_fixtures"
        phx-submit="filter_fixtures"
        class="mb-5 rounded-2xl border border-ink-200 bg-white p-4 shadow-sm"
      >
        <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
          <div :if={@current_admin.role == "regional_coordinator" && @region}>
            <label for="venue-filter" class="mb-2 block text-sm font-semibold text-ink-800">
              Filter by venue
            </label>
            <select
              id="venue-filter"
              name="venue_id"
              class="w-full rounded-full border border-ink-300 bg-white px-4 py-2.5 text-sm text-ink-950 focus:border-red-500 focus:outline-none focus:ring-[3px] focus:ring-red-500/15"
            >
              <option value="">All venues</option>
              <option
                :for={venue_option <- @region_venues}
                value={venue_option.id}
                selected={@venue_filter_id == venue_option.id}
              >
                {venue_option.name}
              </option>
            </select>
          </div>

          <div>
            <label for="group-filter" class="mb-2 block text-sm font-semibold text-ink-800">
              Filter by group
            </label>
            <select
              id="group-filter"
              name="group_name"
              class="w-full rounded-full border border-ink-300 bg-white px-4 py-2.5 text-sm text-ink-950 focus:border-red-500 focus:outline-none focus:ring-[3px] focus:ring-red-500/15"
            >
              <option value="">All groups</option>
              <option
                :for={group <- @available_groups}
                value={group}
                selected={@group_filter == group}
              >
                {group}
              </option>
            </select>
          </div>

          <div class="md:col-span-2">
            <label for="player-search" class="mb-2 block text-sm font-semibold text-ink-800">
              Search player
            </label>
            <div class="flex flex-col gap-2 sm:flex-row">
              <input
                id="player-search"
                name="player_search"
                value={@player_search}
                placeholder="Name or username"
                class="min-h-11 w-full rounded-full border border-ink-300 bg-white px-4 py-2.5 text-sm text-ink-950 placeholder:text-ink-400 focus:border-red-500 focus:outline-none focus:ring-[3px] focus:ring-red-500/15"
              />
              <button
                id="fixture-search-button"
                type="submit"
                class="inline-flex min-h-11 items-center justify-center gap-2 rounded-full bg-ink-950 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink-950 sm:w-auto"
              >
                <.icon name="hero-magnifying-glass" class="size-4" /> Search
              </button>
            </div>
          </div>
        </div>
        <button
          id="clear-fixture-filters"
          type="button"
          phx-click="clear_filters"
          class="mt-3 text-sm font-semibold text-red-600 hover:text-red-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
        >
          Clear filters
        </button>
      </form>

      <div
        :if={is_nil(@venue) && is_nil(@region)}
        class="rounded-2xl border border-amber-200 bg-amber-50 px-5 py-6 text-sm text-amber-900"
      >
        <%= if @current_admin.role == "regional_coordinator" do %>
          Your admin account is not assigned to a region yet. Ask a Tournament Director or Super Admin to assign one.
        <% else %>
          Your admin account is not assigned to a venue yet. Ask a Tournament Director or Super Admin to assign one.
        <% end %>
      </div>

      <div
        :if={(@venue || @region) && @total_fixtures_count == 0}
        class="rounded-2xl border border-ink-200 bg-white px-5 py-9 text-center text-sm text-ink-400 shadow-sm"
      >
        No fixtures have been scheduled at this venue yet.
      </div>

      <div :if={@total_fixtures_count > 0} class="grid grid-cols-1 gap-3.5 xl:grid-cols-2">
        <AdminComponents.card :for={fixture <- @page_fixtures} class="p-4 sm:p-5">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-ink-100 px-2.5 py-1 text-xs font-semibold text-ink-700">
                {fixture_group(fixture)}
              </span>
              <span class={[
                "rounded-full px-2.5 py-1 text-xs font-semibold",
                fixture_status_class(fixture)
              ]}>
                {fixture_status_label(fixture)}
              </span>
            </div>
            <span class="font-mono text-xs text-ink-500">{fixture.match_id || "Fixture"}</span>
          </div>

          <div class="mb-4 text-[15px] font-semibold text-ink-950">
            <span>{Competitions.participant_name(fixture.participant_a)}</span>
            <%= if fixture_score(fixture) do %>
              <span class="ml-1 rounded-md bg-green-50 px-1.5 py-0.5 font-bold text-green-700">
                ({elem(fixture_score(fixture), 0)})
              </span>
              <span class="mx-1 font-normal text-ink-400">vs</span>
              <span class="rounded-md bg-green-50 px-1.5 py-0.5 font-bold text-green-700">
                ({elem(fixture_score(fixture), 1)})
              </span>
            <% else %>
              <span class="mx-1 font-normal text-ink-400">vs</span>
            <% end %>
            <span>{Competitions.participant_name(fixture.participant_b)}</span>
          </div>

          <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <.contact participant={fixture.participant_a} />
            <.contact participant={fixture.participant_b} />
          </div>

          <div class="mt-4 border-t border-ink-100 pt-3 text-xs text-ink-500">
            <span :if={fixture.scheduled_at}>
              {fixture_date(fixture)} · {fixture_time(fixture)}
            </span>
            <span :if={!fixture.scheduled_at}>Grassroots self-organised · play by deadline</span>
          </div>
        </AdminComponents.card>
      </div>

      <nav
        :if={@total_pages > 1}
        id="fixture-pagination"
        aria-label="Fixture pages"
        class="mt-6 flex flex-col items-center justify-between gap-3 rounded-2xl border border-ink-200 bg-white p-3 shadow-sm sm:flex-row"
      >
        <button
          id="fixture-previous-page"
          type="button"
          phx-click="change_page"
          phx-value-page={@page - 1}
          disabled={@page == 1}
          class="min-h-10 w-full rounded-full border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 transition hover:border-ink-950 hover:text-ink-950 disabled:cursor-not-allowed disabled:opacity-40 sm:w-auto"
        >
          Previous
        </button>
        <span class="text-sm text-ink-500">Page {@page} of {@total_pages}</span>
        <button
          id="fixture-next-page"
          type="button"
          phx-click="change_page"
          phx-value-page={@page + 1}
          disabled={@page == @total_pages}
          class="min-h-10 w-full rounded-full bg-ink-950 px-4 py-2 text-sm font-semibold text-white transition hover:bg-ink-900 disabled:cursor-not-allowed disabled:opacity-40 sm:w-auto"
        >
          Next
        </button>
      </nav>
    </AdminComponents.app_shell>
    """
  end

  attr :participant, :map, required: true

  defp contact(assigns) do
    ~H"""
    <div class="rounded-xl bg-ink-50 px-3 py-2.5">
      <div class="mb-1 text-xs font-semibold text-ink-700">
        {Competitions.participant_name(@participant)}
      </div>
      <a
        :if={participant_phone(@participant)}
        href={"tel:#{participant_phone(@participant)}"}
        class="inline-flex min-h-10 items-center gap-1.5 text-sm font-semibold text-green-700 hover:text-green-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-600"
      >
        <.icon name="hero-phone" class="size-4" />
        {participant_phone(@participant)}
      </a>
      <span :if={!participant_phone(@participant)} class="text-xs text-ink-400">
        No phone number recorded
      </span>
    </div>
    """
  end

  defp fixture_group(%{round: %{group: %{name: name}}}) when is_binary(name), do: name
  defp fixture_group(_fixture), do: "Knockout"

  defp fixture_status_class(%{status: "verified"}), do: "bg-green-50 text-green-700"
  defp fixture_status_class(%{status: "completed"}), do: "bg-amber-50 text-amber-700"
  defp fixture_status_class(%{status: "walkover"}), do: "bg-amber-50 text-amber-700"
  defp fixture_status_class(%{status: "postponed"}), do: "bg-red-50 text-red-700"
  defp fixture_status_class(_fixture), do: "bg-ink-100 text-ink-500"

  defp fixture_status_label(%{status: "completed"}), do: "Pending approval"
  defp fixture_status_label(%{status: "verified"}), do: "Approved"

  defp fixture_status_label(%{status: status}) when is_binary(status),
    do: String.capitalize(status)

  defp fixture_status_label(_fixture), do: "Scheduled"

  defp fixture_score(%{
         result: %{score: %{"participant_a_frames" => a, "participant_b_frames" => b}}
       }),
       do: {a, b}

  defp fixture_score(_fixture), do: nil

  defp participant_phone(%{player: %{mobile_number: mobile_number}}), do: mobile_number
  defp participant_phone(%{team: %{captain: %{mobile_number: mobile_number}}}), do: mobile_number
  defp participant_phone(_participant), do: nil

  defp fixture_date(fixture) do
    fixture
    |> Competitions.fixture_time_in_eat()
    |> Calendar.strftime("%b %-d, %Y")
  end

  defp fixture_time(fixture) do
    fixture
    |> Competitions.fixture_time_in_eat()
    |> Calendar.strftime("%H:%M")
  end

  defp valid_region_venue_id(_venues, ""), do: nil

  defp valid_region_venue_id(venues, venue_id) when is_binary(venue_id) do
    case Enum.find(venues, &(&1.id == venue_id)) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp valid_region_venue_id(_venues, _venue_id), do: nil

  defp download_path(nil), do: ~p"/admin/venue-fixtures/export.pdf"

  defp download_path(venue_id), do: ~p"/admin/venue-fixtures/export.pdf?venue_id=#{venue_id}"

  defp parse_page(page, total_pages) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> parse_page(page, total_pages)
      _ -> 1
    end
  end

  defp parse_page(page, total_pages) when is_integer(page),
    do: page |> max(1) |> min(max(total_pages, 1))

  defp parse_page(_page, _total_pages), do: 1

  # The admin's fixed scope for the download link and (for a regional
  # coordinator) the venue sub-filter — a venue rep's own venue_id always,
  # never reset by filtering, since their export always covers just their
  # venue regardless of what's selected in the (regional-coordinator-only)
  # venue dropdown.
  defp scope_venue_filter_id(%Admin{role: "venue_representative", venue_id: venue_id}, _selected),
    do: venue_id

  defp scope_venue_filter_id(%Admin{role: "regional_coordinator"}, selected), do: selected
  defp scope_venue_filter_id(%Admin{}, _selected), do: nil

  defp apply_filters(params, socket) do
    admin = socket.assigns.current_admin
    venue_id = Map.get(params, "venue_id", "")
    selected_venue_id = valid_region_venue_id(socket.assigns.region_venues, venue_id)

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:venue_filter_id, scope_venue_filter_id(admin, selected_venue_id))
      |> load_available_groups()

    requested_group = Map.get(params, "group_name", "")

    group_filter =
      if requested_group in ["" | socket.assigns.available_groups], do: requested_group, else: ""

    player_search = Map.get(params, "player_search", "") |> String.trim()

    {:noreply,
     socket
     |> assign(:group_filter, group_filter)
     |> assign(:player_search, player_search)
     |> load_fixtures()}
  end

  # Dropdown options reflect the venue selection only (not the group/player
  # filters) — same scope `load_fixtures/1` uses when it isn't also
  # narrowed by group_name/player_search, matching the pre-pagination
  # behaviour where this was computed from the venue-filtered set before
  # the group/player filters were applied.
  defp load_available_groups(socket) do
    %{current_admin: admin, venue_filter_id: venue_filter_id} = socket.assigns

    available_groups =
      case admin.role do
        "regional_coordinator" ->
          if admin.region_id,
            do: Competitions.list_region_fixture_group_names(admin.region_id, venue_filter_id),
            else: []

        "venue_representative" ->
          if admin.venue_id,
            do: Competitions.list_venue_fixture_group_names(admin.venue_id),
            else: []

        _ ->
          []
      end

    assign(socket, :available_groups, available_groups)
  end

  defp load_fixtures(socket) do
    %{
      current_admin: admin,
      group_filter: group_filter,
      player_search: player_search,
      venue_filter_id: venue_filter_id,
      page: page
    } = socket.assigns

    shared_opts = [group_name: group_filter, player_search: player_search]

    {total_count, fetch_page} =
      case admin.role do
        "regional_coordinator" ->
          if admin.region_id do
            opts = Keyword.put(shared_opts, :venue_id, venue_filter_id)

            {Competitions.count_region_fixtures(admin.region_id, opts),
             fn page ->
               Competitions.list_region_fixtures_page(
                 admin.region_id,
                 Keyword.put(opts, :page, page)
               )
             end}
          else
            {0, fn _page -> [] end}
          end

        "venue_representative" ->
          if admin.venue_id do
            {Competitions.count_venue_fixtures(admin.venue_id, shared_opts),
             fn page ->
               Competitions.list_venue_fixtures_page(
                 admin.venue_id,
                 Keyword.put(shared_opts, :page, page)
               )
             end}
          else
            {0, fn _page -> [] end}
          end

        _ ->
          {0, fn _page -> [] end}
      end

    per_page = Competitions.venue_fixtures_per_page()
    total_pages = max(1, ceil(total_count / per_page))
    page = page |> max(1) |> min(total_pages)

    socket
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:total_fixtures_count, total_count)
    |> assign(:page_fixtures, fetch_page.(page))
  end
end
