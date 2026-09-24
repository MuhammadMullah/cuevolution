defmodule CuevolutionWeb.GroupManagementLive do
  @moduledoc """
  Admin "Groups" page (spec 006, extended by spec 012). Stage + region +
  category tabs, same as always. Two distinct experiences live under the
  same route, matching the design source (`project-scope/Quevolution/Cuevolution
  Admin.dc.html`'s single `GROUPS` section, `grOn`/`grOff` branch) rather than
  the three separate pages an earlier pass split this into:

  - Grassroots, Individual Male/Female, with a venue selected (`grassroots_singles?/1`):
    the full formula-driven draw lifecycle (propose → deal → approve →
    publish → redraw) plus a "Groups" / "Group standings" tab pair, both
    inline on this page. This replaces the standalone `Admin.DrawWizardLive`
    and `Admin.GroupStandingsLive` routes, which are gone.
  - Everything else (Regional, Team category, or no venue selected yet):
    the original manual create-group / assign-member flow, unchanged.

  Grassroots groups are venue-scoped (FR-003); Regional groups are
  region-scoped (FR-004). Neither stage ever creates a knockout bracket —
  those are Circuit/Finals stage+category constructs, unrelated to groups.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Draw, Group, StageParticipation}
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  @categories ~w(male female team)
  @draw_states ~w(draft previewed approved published)

  def mount(_params, _session, socket) do
    stages =
      Competitions.list_stages() |> Enum.filter(&(&1.name in ["Grassroots", "Regional"]))

    regions = Accounts.list_regions()
    stage = List.first(stages)
    region = List.first(regions)

    {:ok,
     socket
     |> assign(
       page_title: "Groups",
       stages: stages,
       regions: regions,
       categories: @categories,
       stage: stage,
       region: region,
       category: List.first(@categories),
       venue: nil,
       form: to_form(%{}, as: :group),
       open_group_ids: MapSet.new(),
       open_fixtures: %{},
       gr_view: :groups,
       proposal: nil,
       group_count: nil,
       sizes: nil,
       draw: nil,
       redraw_open: false,
       redraw_reason: "",
       confirm_close: false,
       tie_resolution: nil
     )
     |> load_venues()
     |> load_scope()}
  end

  ## Shared stage/region/venue/category navigation (used by both experiences)

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> load_venues()
     |> load_scope()}
  end

  def handle_event("select_region", %{"id" => id}, socket) do
    region = Enum.find(socket.assigns.regions, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:region, region)
     |> load_venues()
     |> load_scope()}
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply, socket |> assign(:category, category) |> load_scope()}
  end

  def handle_event("select_venue", %{"id" => id}, socket) do
    venue = Enum.find(socket.assigns.venues, &(&1.id == id))
    {:noreply, socket |> assign(:venue, venue) |> load_scope()}
  end

  def handle_event("select_gr_view", %{"view" => view}, socket) do
    view = if view == "standings", do: :standings, else: :groups
    {:noreply, socket |> assign(:gr_view, view) |> load_gr_standings_if_needed()}
  end

  ## grOff: manual create-group / assign-member flow (unchanged behavior)

  def handle_event("create_group", %{"group" => %{"name" => name}}, socket) do
    attrs = %{
      stage_id: socket.assigns.stage.id,
      region_id: socket.assigns.region.id,
      venue_id:
        if(grassroots?(socket.assigns) && socket.assigns.venue, do: socket.assigns.venue.id),
      category: socket.assigns.category,
      name: name
    }

    case Competitions.create_group(attrs) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{group.name}\" created.")
         |> assign(:form, to_form(%{}, as: :group))
         |> load_groups()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :group))}
    end
  end

  def handle_event("toggle_group", %{"id" => id}, socket) do
    open_group_ids =
      if MapSet.member?(socket.assigns.open_group_ids, id) do
        MapSet.delete(socket.assigns.open_group_ids, id)
      else
        MapSet.put(socket.assigns.open_group_ids, id)
      end

    socket = assign(socket, :open_group_ids, open_group_ids)

    socket =
      if grassroots_singles?(socket.assigns) and MapSet.member?(open_group_ids, id) and
           not Map.has_key?(socket.assigns.open_fixtures, id) do
        Phoenix.Component.update(
          socket,
          :open_fixtures,
          &Map.put(&1, id, Competitions.list_fixtures_for_group(id))
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event(
        "assign_to_group",
        %{"group_id" => group_id, "participation_id" => pid},
        socket
      ) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))
    participation = Enum.find(socket.assigns.unassigned, &(&1.id == pid))

    socket =
      case Competitions.assign_to_group(participation, group) do
        {:ok, _membership} ->
          socket
          |> put_flash(:info, "Added to #{group.name}.")
          |> load_groups()
          |> load_unassigned()

        {:error, :category_mismatch} ->
          put_flash(socket, :error, "Couldn't add — category mismatch.")

        {:error, _changeset} ->
          put_flash(socket, :error, "Couldn't add — already in this group?")
      end

    {:noreply, socket}
  end

  ## grOn: formula-driven draw lifecycle

  def handle_event("propose", _params, socket) do
    %{stage: stage, venue: venue, category: category} = socket.assigns

    case Competitions.propose_draw(stage.id, venue.id, category) do
      {:ok, proposal} ->
        {:noreply,
         socket
         |> assign(:proposal, proposal)
         |> assign(:group_count, proposal.group_count)
         |> assign(:sizes, proposal.sizes)}

      {:error, :below_minimum} ->
        {:noreply,
         put_flash(socket, :error, "At least four verified entrants are required to run a draw.")}
    end
  end

  def handle_event("dec_group_count", _params, socket),
    do: {:noreply, adjust_group_count(socket, -1)}

  def handle_event("inc_group_count", _params, socket),
    do: {:noreply, adjust_group_count(socket, 1)}

  def handle_event("create_draw", _params, socket) do
    %{stage: stage, venue: venue, category: category} = socket.assigns
    override = override_value(socket)

    with {:ok, draw} <-
           Competitions.create_draw(
             %{stage_id: stage.id, venue_id: venue.id, category: category},
             socket.assigns.current_admin
           ),
         {:ok, _groups} <-
           Competitions.deal_draw(draw, socket.assigns.current_admin, override) do
      {:noreply,
       socket
       |> put_flash(:info, "Draw dealt. Review the groups before approving.")
       |> load_gr()}
    else
      {:error, :below_minimum} ->
        {:noreply,
         put_flash(socket, :error, "At least four verified entrants are required to run a draw.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the draw: #{format_error(reason)}")}
    end
  end

  def handle_event("advance_draw", %{"state" => state}, socket) do
    case Competitions.advance_draw_state(socket.assigns.draw, socket.assigns.current_admin, state) do
      {:ok, %{draw: _draw}} ->
        {:noreply, load_gr(socket)}

      {:ok, _draw} ->
        {:noreply, load_gr(socket)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Couldn't advance the draw: #{format_error(reason)}")}
    end
  end

  def handle_event("open_redraw", _params, socket),
    do: {:noreply, assign(socket, redraw_open: true)}

  def handle_event("cancel_redraw", _params, socket),
    do: {:noreply, assign(socket, redraw_open: false, redraw_reason: "")}

  def handle_event("update_redraw_reason", %{"reason" => reason}, socket),
    do: {:noreply, assign(socket, :redraw_reason, reason)}

  def handle_event("confirm_redraw", _params, socket) do
    case Competitions.redraw(
           socket.assigns.draw,
           socket.assigns.current_admin,
           socket.assigns.redraw_reason
         ) do
      {:ok, _new_draft} ->
        {:noreply,
         socket
         |> assign(
           draw: nil,
           proposal: nil,
           group_count: nil,
           sizes: nil,
           redraw_open: false,
           redraw_reason: "",
           open_group_ids: MapSet.new(),
           open_fixtures: %{}
         )
         |> put_flash(:info, "A new draft draw was created — propose and deal it below.")
         |> load_gr()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't redraw: #{format_error(reason)}")}
    end
  end

  ## grOn: standings sub-view

  def handle_event("open_tie", %{"participant-a" => a, "participant-b" => b}, socket) do
    names = socket.assigns.standings_names
    resolution = %{winner: a, loser: b, winner_name: names[a], loser_name: names[b]}
    {:noreply, assign(socket, :tie_resolution, resolution)}
  end

  def handle_event("cancel_tie", _params, socket),
    do: {:noreply, assign(socket, :tie_resolution, nil)}

  def handle_event(
        "confirm_resolve_tie",
        %{"group-id" => group_id, "winner" => winner, "loser" => loser},
        socket
      ) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))

    case Competitions.resolve_tie(group, socket.assigns.current_admin, winner, loser) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tie resolved.")
         |> assign(:tie_resolution, nil)
         |> load_gr_standings()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not resolve tie: #{inspect(reason)}")}
    end
  end

  def handle_event("confirm_close", _params, socket),
    do: {:noreply, assign(socket, :confirm_close, true)}

  def handle_event("cancel_close", _params, socket),
    do: {:noreply, assign(socket, :confirm_close, false)}

  def handle_event("close_stage", _params, socket) do
    ids = Enum.map(socket.assigns.qualifiers, & &1.participant_id)

    case Competitions.close_grassroots_stage(
           socket.assigns.stage.id,
           socket.assigns.category,
           socket.assigns.current_admin,
           ids
         ) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Qualifiers advanced.") |> assign(:confirm_close, false)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not close stage: #{inspect(reason)}")}
    end
  end

  ## Loading

  # Takes an assigns map, not a socket — deliberately, so the exact same
  # function works both from `handle_event`/loaders (`grassroots?(socket.assigns)`)
  # and directly from the template (`grassroots_singles?(assigns)`), which
  # only ever sees `assigns`, never `socket`.
  defp grassroots?(assigns), do: assigns.stage.name == "Grassroots"

  defp grassroots_singles?(assigns),
    do: grassroots?(assigns) and assigns.category in ~w(male female) and !!assigns.venue

  defp load_venues(socket) do
    if grassroots?(socket.assigns) do
      venues = Venues.list_active_for_region(socket.assigns.region.id)
      assign(socket, venues: venues, venue: List.first(venues))
    else
      assign(socket, venues: [], venue: nil)
    end
  end

  # Single entry point after any scope change (stage/region/venue/category) —
  # routes to whichever of the two experiences applies.
  defp load_scope(socket) do
    socket =
      assign(socket,
        gr_view: :groups,
        proposal: nil,
        group_count: nil,
        sizes: nil,
        redraw_open: false,
        redraw_reason: "",
        open_group_ids: MapSet.new(),
        open_fixtures: %{},
        confirm_close: false,
        tie_resolution: nil
      )

    if grassroots_singles?(socket.assigns),
      do: load_gr(socket),
      else: socket |> load_groups() |> load_unassigned()
  end

  defp load_gr(socket) do
    %{stage: stage, venue: venue, category: category} = socket.assigns
    draw = Competitions.latest_draw(stage.id, venue.id, category)
    dealt? = draw && draw.state != "draft"

    socket =
      assign(socket,
        draw: draw,
        groups: if(dealt?, do: Competitions.list_groups_for_draw(draw.id), else: [])
      )

    if socket.assigns.gr_view == :standings, do: load_gr_standings(socket), else: socket
  end

  defp load_gr_standings_if_needed(socket) do
    if socket.assigns.gr_view == :standings and grassroots_singles?(socket.assigns),
      do: load_gr_standings(socket),
      else: socket
  end

  defp load_gr_standings(socket) do
    %{stage: stage, category: category, groups: groups} = socket.assigns
    config = Competitions.get_or_create_group_config(stage.id, category)

    tables =
      Enum.map(groups, fn group ->
        rows = group |> Competitions.grassroots_group_standings() |> name_rows()

        fixtures =
          Map.get(socket.assigns.open_fixtures, group.id) ||
            Competitions.list_fixtures_for_group(group.id)

        final? = fixtures != [] and Enum.all?(fixtures, &(&1.status in ["verified", "walkover"]))
        top = Enum.take(rows, config.advancer_count)
        %{group: group, rows: rows, final?: final?, top: top}
      end)

    best_rest =
      stage.id |> Competitions.best_of_rest_qualifiers(category) |> name_rows()

    all_top =
      Group
      |> where([g], g.stage_id == ^stage.id and g.category == ^category)
      |> Repo.all()
      |> Enum.flat_map(fn g ->
        g |> Competitions.grassroots_group_standings() |> Enum.take(config.advancer_count)
      end)
      |> name_rows()

    qualifiers = Enum.uniq_by(all_top ++ best_rest, & &1.participant_id)
    names = tables |> Enum.flat_map(& &1.rows) |> Map.new(&{&1.participant_id, &1.name})

    assign(socket,
      standings_tables: tables,
      standings_names: names,
      config: config,
      best_rest_qualifiers: best_rest,
      qualifiers: qualifiers
    )
  end

  defp load_groups(socket) do
    scope =
      if grassroots?(socket.assigns) && socket.assigns.venue,
        do: {:venue_id, socket.assigns.venue.id},
        else: {:region_id, socket.assigns.region.id}

    assign(
      socket,
      :groups,
      if(grassroots?(socket.assigns) && is_nil(socket.assigns.venue),
        do: [],
        else: Competitions.list_groups(socket.assigns.stage.id, socket.assigns.category, scope)
      )
    )
  end

  defp load_unassigned(socket) do
    assign(
      socket,
      :unassigned,
      Competitions.list_unassigned_participations(
        socket.assigns.stage.id,
        socket.assigns.region.id,
        socket.assigns.category
      )
    )
  end

  defp adjust_group_count(%{assigns: %{group_count: nil}} = socket, _delta), do: socket

  defp adjust_group_count(%{assigns: %{proposal: proposal, group_count: count}} = socket, delta) do
    new_count = max(1, count + delta)
    sizes = Competitions.balanced_sizes(proposal.entrant_count, new_count)
    assign(socket, group_count: new_count, sizes: sizes)
  end

  defp override_value(%{assigns: %{proposal: %{group_count: same}, group_count: same}}), do: nil
  defp override_value(%{assigns: %{group_count: count}}), do: count

  defp name_rows(rows) do
    ids = Enum.map(rows, & &1.participant_id)

    names =
      Repo.all(from p in StageParticipation, where: p.id in ^ids, preload: :player)
      |> Map.new(&{&1.id, player_name(&1)})

    Enum.map(rows, &Map.put(&1, :name, Map.get(names, &1.participant_id, "Unknown")))
  end

  defp player_name(%{player: %{first_name: first, last_name: last}}), do: "#{first} #{last}"
  defp player_name(_), do: "Team"

  ## View helpers

  defp participant_name(%{player_id: nil, team: team}), do: team.name
  defp participant_name(%{player: player}), do: "#{player.first_name} #{player.last_name}"

  defp scope_label(assigns) do
    venue_or_region =
      if assigns.stage.name == "Grassroots" && assigns.venue,
        do: assigns.venue.name,
        else: assigns.region.name

    "#{assigns.stage.name} · #{venue_or_region} · #{category_label(assigns.category)}"
  end

  defp category_label("male"), do: "Individual Male"
  defp category_label("female"), do: "Individual Female"
  defp category_label("team"), do: "Teams"

  defp draw_step_index(nil), do: 0

  defp draw_step_index(%Draw{state: state}),
    do: Enum.find_index(@draw_states, &(&1 == state)) || 0

  defp draw_step_label(index), do: Enum.at(@draw_states, index) |> String.capitalize()

  defp ngettext_group(1), do: "group"
  defp ngettext_group(_count), do: "groups"

  defp fixture_progress(fixtures),
    do: {Enum.count(fixtures, &(&1.status in ["verified", "walkover"])), length(fixtures)}

  defp member_progress(fixtures, participation_id) do
    played =
      Enum.count(fixtures, fn f ->
        f.status in ["verified", "walkover"] and
          (f.participant_a_id == participation_id or f.participant_b_id == participation_id)
      end)

    total =
      Enum.count(fixtures, fn f ->
        f.participant_a_id == participation_id or f.participant_b_id == participation_id
      end)

    "#{played}/#{total}"
  end

  defp fixture_pair(%{participant_a: a, participant_b: b}),
    do: "#{participant_name(a)} vs #{participant_name(b)}"

  defp tie_opponent(rows, participant_id) do
    case Enum.find(rows, fn row -> row.tied and row.participant_id != participant_id end) do
      nil -> ""
      row -> row.participant_id
    end
  end

  defp format_error(:invalid_group_count), do: "the group count is invalid"
  defp format_error(:already_dealt), do: "this draw has already been dealt"
  defp format_error(:unauthorized), do: "you do not have permission"
  defp format_error(:results_exist), do: "results already exist — redraw is blocked"
  defp format_error(:reason_required), do: "a reason is required"
  defp format_error(reason), do: inspect(reason)

  # Matches CuevolutionWeb.PlayerComponents' @stage_styles palette (the
  # actual app design system — gray/Kenya-Green/Kenya-Red/ink-950), not the
  # Grassroots/Regional colors in the reference mockup's latest revision.
  defp stage_tab_active_class("Grassroots"), do: "border-ink-500 bg-ink-100 text-ink-700"
  defp stage_tab_active_class("Regional"), do: "border-green-500 bg-green-100 text-green-700"
  defp stage_tab_active_class(_stage), do: "border-red-500 bg-red-50 text-red-700"
end
