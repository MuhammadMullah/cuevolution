defmodule CuevolutionWeb.VenueFixturesLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  @fixtures_per_page 10

  def mount(_params, _session, socket) do
    admin = Repo.preload(socket.assigns.current_admin, [:venue, :region])

    {fixtures, venue, region_venues, venue_filter_id} =
      case admin.role do
        "regional_coordinator" ->
          venues =
            if admin.region_id, do: Venues.list_active_for_region(admin.region_id), else: []

          fixtures =
            if admin.region_id,
              do: Competitions.list_fixtures_for_region(admin.region_id),
              else: []

          {fixtures, nil, venues, nil}

        "venue_representative" ->
          fixtures =
            if admin.venue_id, do: Competitions.list_fixtures_for_venue(admin.venue_id), else: []

          {fixtures, admin.venue, [], admin.venue_id}

        _ ->
          {[], nil, [], nil}
      end

    {:ok,
     assign(socket,
       page_title: "Venue Fixtures",
       current_admin: admin,
       venue: venue,
       region: admin.region,
       region_venues: region_venues,
       venue_filter_id: venue_filter_id,
       all_fixtures: fixtures,
       fixtures: fixtures,
       available_groups: group_options(fixtures),
       group_filter: "",
       player_search: "",
       page: 1,
       page_fixtures: page_fixtures(fixtures, 1),
       total_pages: total_pages(fixtures)
     )}
  end

  def handle_event("filter_venue", params, socket), do: apply_filters(params, socket)
  def handle_event("filter_fixtures", params, socket), do: apply_filters(params, socket)

  def handle_event("clear_filters", _params, socket) do
    apply_filters(%{"venue_id" => "", "group_name" => "", "player_search" => ""}, socket)
  end

  def handle_event("change_page", %{"page" => page}, socket) do
    page = parse_page(page, socket.assigns.total_pages)

    {:noreply,
     assign(socket,
       page: page,
       page_fixtures: page_fixtures(socket.assigns.fixtures, page)
     )}
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
          <span :if={@fixtures != []} class="font-mono text-xs text-ink-500">
            {length(@fixtures)} fixtures
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
        :if={(@venue || @region) && @fixtures == []}
        class="rounded-2xl border border-ink-200 bg-white px-5 py-9 text-center text-sm text-ink-400 shadow-sm"
      >
        No fixtures have been scheduled at this venue yet.
      </div>

      <div :if={@fixtures != []} class="grid grid-cols-1 gap-3.5 xl:grid-cols-2">
        <AdminComponents.card :for={fixture <- @page_fixtures} class="p-4 sm:p-5">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-ink-100 px-2.5 py-1 text-xs font-semibold text-ink-700">
                {fixture_group(fixture)}
              </span>
              <span class={[
                "rounded-full px-2.5 py-1 text-xs font-semibold capitalize",
                fixture_status_class(fixture)
              ]}>
                {fixture.status || "scheduled"}
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

  defp fixture_status_class(%{status: status}) when status in ["completed", "verified"],
    do: "bg-green-50 text-green-700"

  defp fixture_status_class(%{status: "walkover"}), do: "bg-amber-50 text-amber-700"
  defp fixture_status_class(%{status: "postponed"}), do: "bg-red-50 text-red-700"
  defp fixture_status_class(_fixture), do: "bg-ink-100 text-ink-500"

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

  defp page_fixtures(fixtures, page),
    do: Enum.slice(fixtures, (page - 1) * @fixtures_per_page, @fixtures_per_page)

  defp total_pages([]), do: 0
  defp total_pages(fixtures), do: ceil(length(fixtures) / @fixtures_per_page)

  defp parse_page(page, total_pages) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> parse_page(page, total_pages)
      _ -> 1
    end
  end

  defp parse_page(page, total_pages) when is_integer(page),
    do: page |> max(1) |> min(max(total_pages, 1))

  defp parse_page(_page, _total_pages), do: 1

  defp apply_filters(params, socket) do
    admin = socket.assigns.current_admin
    venue_id = Map.get(params, "venue_id", "")
    selected_venue_id = valid_region_venue_id(socket.assigns.region_venues, venue_id)

    base_fixtures =
      if admin.role == "regional_coordinator" and admin.region_id do
        Competitions.list_fixtures_for_region(admin.region_id, selected_venue_id)
      else
        socket.assigns.all_fixtures
      end

    available_groups = group_options(base_fixtures)
    requested_group = Map.get(params, "group_name", "")
    group_filter = if requested_group in ["" | available_groups], do: requested_group, else: ""
    player_search = Map.get(params, "player_search", "") |> String.trim()

    fixtures =
      Enum.filter(base_fixtures, fn fixture ->
        (group_filter == "" or fixture_group(fixture) == group_filter) and
          fixture_matches_search?(fixture, player_search)
      end)

    {:noreply,
     assign(socket,
       fixtures: fixtures,
       available_groups: available_groups,
       venue_filter_id: selected_venue_id,
       group_filter: group_filter,
       player_search: player_search,
       page: 1,
       page_fixtures: page_fixtures(fixtures, 1),
       total_pages: total_pages(fixtures)
     )}
  end

  defp group_options(fixtures) do
    fixtures
    |> Enum.map(&fixture_group/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp fixture_matches_search?(_fixture, ""), do: true

  defp fixture_matches_search?(fixture, query) do
    query = String.downcase(query)

    participant_matches_search?(fixture.participant_a, query) or
      participant_matches_search?(fixture.participant_b, query)
  end

  defp participant_matches_search?(participant, query) do
    participant
    |> participant_search_values()
    |> Enum.any?(&String.contains?(String.downcase(&1), query))
  end

  defp participant_search_values(%{
         player: %{first_name: first, last_name: last, username: username}
       }),
       do: [first, last, "#{first} #{last}", username]

  defp participant_search_values(%{team: %{name: name, captain: captain}}),
    do: [name | participant_search_values(captain)]

  defp participant_search_values(_participant), do: []
end
