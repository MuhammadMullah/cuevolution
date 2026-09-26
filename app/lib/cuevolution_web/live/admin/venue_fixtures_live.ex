defmodule CuevolutionWeb.VenueFixturesLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias Cuevolution.Repo
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    admin = Repo.preload(socket.assigns.current_admin, :venue)

    fixtures =
      if admin.venue_id, do: Competitions.list_fixtures_for_venue(admin.venue_id), else: []

    {:ok,
     assign(socket,
       page_title: "Venue Fixtures",
       current_admin: admin,
       venue: admin.venue,
       fixtures: fixtures
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
        </div>
        <div class="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center">
          <span :if={@fixtures != []} class="font-mono text-xs text-ink-500">
            {length(@fixtures)} fixtures
          </span>
          <a
            :if={@venue}
            href={~p"/admin/venue-fixtures/export.csv"}
            download
            class="inline-flex min-h-10 items-center justify-center gap-2 rounded-full border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 transition hover:border-ink-950 hover:text-ink-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink-950"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download CSV
          </a>
        </div>
      </div>

      <div
        :if={is_nil(@venue)}
        class="rounded-2xl border border-amber-200 bg-amber-50 px-5 py-6 text-sm text-amber-900"
      >
        Your admin account is not assigned to a venue yet. Ask a Tournament Director or Super Admin to assign one.
      </div>

      <div
        :if={@venue && @fixtures == []}
        class="rounded-2xl border border-ink-200 bg-white px-5 py-9 text-center text-sm text-ink-400 shadow-sm"
      >
        No fixtures have been scheduled at this venue yet.
      </div>

      <div :if={@fixtures != []} class="grid grid-cols-1 gap-3.5 xl:grid-cols-2">
        <AdminComponents.card :for={fixture <- @fixtures} class="p-4 sm:p-5">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-ink-100 px-2.5 py-1 text-xs font-semibold text-ink-700">
                {fixture_group(fixture)}
              </span>
              <span class="text-xs capitalize text-ink-400">{fixture.status || "scheduled"}</span>
            </div>
            <span class="font-mono text-xs text-ink-500">{fixture.match_id || "Fixture"}</span>
          </div>

          <div class="mb-4 text-[15px] font-semibold text-ink-950">
            {Competitions.participant_name(fixture.participant_a)}
            <span class="font-normal text-ink-400">vs</span>
            {Competitions.participant_name(fixture.participant_b)}
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
end
