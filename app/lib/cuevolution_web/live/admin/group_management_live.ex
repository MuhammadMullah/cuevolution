defmodule CuevolutionWeb.GroupManagementLive do
  @moduledoc """
  Admin "Groups" page (spec 006, extended by spec 012). Stage + region +
  category tabs, same as always. Two distinct experiences live under the
  same route, matching the design source (`project-scope/Quevolution/Cuevolution
  Admin.dc.html`'s single `GROUPS` section, `grOn`/`grOff` branch) rather than
  the three separate pages an earlier pass split this into:

  - The formula-driven draw lifecycle (propose → deal → approve → publish →
    redraw) plus a "Groups" / "Group standings" tab pair, both inline on
    this page, for: Grassroots Individual Male with a venue selected
    (venue-scoped), or Regional Individual Male/Female/Team (region-scoped —
    both genders drawn together under the single "team" category; ladies
    and teams start their tournament here, not at Grassroots). See
    `auto_draw_eligible?/1`. This replaces the standalone
    `Admin.DrawWizardLive` and `Admin.GroupStandingsLive` routes, which are
    gone.
  - Everything else (no venue selected yet, for Grassroots): the original
    manual create-group / assign-member flow, unchanged — stays reachable
    for that case even though Regional now always routes onto the engine
    above.

  Grassroots groups are venue-scoped (FR-003); Regional groups are
  region-scoped (FR-004). Neither stage ever creates a knockout bracket —
  those are Circuit/Finals stage+category constructs, unrelated to groups.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Draw, Stage, StageParticipation}
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.Admin.MatchEntryComponent
  alias CuevolutionWeb.AdminComponents

  @categories ~w(male female team)
  @draw_states ~w(draft previewed approved published)

  def mount(_params, _session, socket) do
    current_admin = Repo.preload(socket.assigns.current_admin, venue: :region)
    venue_rep? = current_admin.role == "venue_representative"

    stages =
      Competitions.list_stages()
      |> Enum.filter(&Stage.round_robin?/1)

    stages = if venue_rep?, do: Enum.filter(stages, &Stage.grassroots?/1), else: stages

    regions =
      if venue_rep? && current_admin.venue && current_admin.venue.region,
        do: [current_admin.venue.region],
        else: Accounts.list_regions()

    stage = List.first(stages)
    region = List.first(regions)
    categories = categories_for_stage(stage)

    {:ok,
     socket
     |> assign(
       page_title: "Groups",
       current_admin: current_admin,
       venue_rep?: venue_rep?,
       can_manage_groups?: Admin.can?(current_admin, :manage_groups),
       can_close_stage?: Admin.can?(current_admin, :advance_participants),
       can_upload_result_sheets?: Admin.can?(current_admin, :record_results),
       result_sheets: [],
       venue_ready_early?: false,
       stages: stages,
       regions: regions,
       categories: categories,
       stage: stage,
       region: region,
       category: List.first(categories),
       venue: nil,
       form: to_form(%{}, as: :group),
       open_group_ids: MapSet.new(),
       gr_open_group_id: nil,
       gr_selected_member_id: nil,
       gr_view: :groups,
       standings_view: :per_group,
       proposal: nil,
       group_count: nil,
       sizes: nil,
       draw: nil,
       group_fixtures: %{},
       redraw_open: false,
       redraw_reason: "",
       confirm_close: false,
       qualifier_search: "",
       qualifier_candidates: [],
       tie_resolution: nil,
       bulk_add_open?: false,
       bulk_add_form: to_form(%{}, as: :bulk_add),
       bulk_add_result: nil,
       selected_fixture_id: nil
     )
     |> allow_upload(:result_sheet,
       accept: ~w(.jpg .jpeg .pdf),
       max_entries: 1,
       max_file_size: 15_000_000
     )
     |> load_venues()
     |> load_scope()}
  end

  ## Shared stage/region/venue/category navigation (used by both experiences)

  def handle_event("select_stage", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.stages, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That stage is not available.")}

      stage ->
        categories = categories_for_stage(stage)

        category =
          if socket.assigns.category in categories,
            do: socket.assigns.category,
            else: List.first(categories)

        {:noreply,
         socket
         |> assign(stage: stage, categories: categories, category: category)
         |> load_venues()
         |> load_scope()}
    end
  end

  def handle_event("select_region", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.regions, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That region is not available.")}

      region ->
        {:noreply,
         socket
         |> assign(:region, region)
         |> load_venues()
         |> load_scope()}
    end
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    if category in socket.assigns.categories,
      do: {:noreply, socket |> assign(:category, category) |> load_scope()},
      else: {:noreply, put_flash(socket, :error, "That category is not available.")}
  end

  def handle_event("select_venue", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.venues, &(&1.id == id)) do
      nil -> {:noreply, put_flash(socket, :error, "That venue is not available.")}
      venue -> {:noreply, socket |> assign(:venue, venue) |> load_scope()}
    end
  end

  def handle_event("select_gr_view", %{"view" => view}, socket) do
    view = if view == "standings", do: :standings, else: :groups
    {:noreply, socket |> assign(:gr_view, view) |> load_gr_standings_if_needed()}
  end

  def handle_event("select_standings_view", %{"view" => view}, socket) do
    view = if view == "overall", do: :overall, else: :per_group
    {:noreply, assign(socket, :standings_view, view)}
  end

  ## grOff: manual create-group / assign-member flow (unchanged behavior)

  def handle_event("create_group", %{"group" => %{"name" => name}}, socket) do
    if socket.assigns.can_manage_groups? do
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
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage groups.")}
    end
  end

  def handle_event("toggle_group", %{"id" => id}, socket) do
    open_group_ids =
      if MapSet.member?(socket.assigns.open_group_ids, id) do
        MapSet.delete(socket.assigns.open_group_ids, id)
      else
        MapSet.put(socket.assigns.open_group_ids, id)
      end

    {:noreply, assign(socket, :open_group_ids, open_group_ids)}
  end

  def handle_event(
        "assign_to_group",
        %{"group_id" => group_id, "participation_id" => pid},
        socket
      ) do
    if socket.assigns.can_manage_groups? do
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
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to manage groups.")}
    end
  end

  ## grOn: formula-driven draw lifecycle

  def handle_event("propose", _params, socket) do
    %{stage: stage, category: category} = socket.assigns

    case Competitions.propose_draw(stage.id, draw_scope(socket.assigns), category) do
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
    %{stage: stage, category: category} = socket.assigns
    override = override_value(socket)

    attrs =
      Map.merge(
        %{stage_id: stage.id, category: category},
        scope_attrs(draw_scope(socket.assigns))
      )

    with {:ok, draw} <-
           Competitions.create_draw(attrs, socket.assigns.current_admin),
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

  def handle_event("reshuffle_draw", _params, socket) do
    case Competitions.reshuffle_draw(socket.assigns.draw, socket.assigns.current_admin) do
      {:ok, _draw} ->
        {:noreply,
         socket
         |> put_flash(:info, "Groups reshuffled. Review the new preview before approving.")
         |> load_gr()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reshuffle: #{format_error(reason)}")}
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
           gr_open_group_id: nil,
           gr_selected_member_id: nil
         )
         |> put_flash(:info, "A new draft draw was created — propose and deal it below.")
         |> load_gr()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't redraw: #{format_error(reason)}")}
    end
  end

  # The fixtures sub-section (below the always-visible member roster) is
  # inert until the draw is published — no fixtures exist before then
  # (FR-008 generates them on the publish transition), matching the
  # design's `toggle:()=>{ if(!grPub) return; ... }`. Only one card's
  # fixtures panel is open at a time (design's `grCardSel` is a single
  # index, not a set). `@group_fixtures` is already loaded for every group
  # (see `load_gr/1`), so this just toggles which one is expanded.
  def handle_event("toggle_gr_card", %{"id" => id}, socket) do
    socket =
      cond do
        is_nil(socket.assigns.draw) or socket.assigns.draw.state != "published" ->
          socket

        socket.assigns.gr_open_group_id == id ->
          assign(socket, gr_open_group_id: nil, gr_selected_member_id: nil)

        true ->
          assign(socket, gr_open_group_id: id, gr_selected_member_id: nil)
      end

    {:noreply, socket}
  end

  def handle_event("select_gr_member", %{"id" => id}, socket) do
    selected = if socket.assigns.gr_selected_member_id == id, do: nil, else: id

    group =
      Enum.find(socket.assigns.groups, fn group ->
        Enum.any?(group.group_memberships, &(&1.stage_participation_id == id))
      end)

    socket =
      if socket.assigns.draw && socket.assigns.draw.state == "published" && group do
        assign(socket, gr_open_group_id: group.id, gr_selected_member_id: selected)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("clear_gr_member_filter", _params, socket),
    do: {:noreply, assign(socket, :gr_selected_member_id, nil)}

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

  def handle_event("confirm_close", _params, socket) do
    if socket.assigns.can_close_stage? do
      {:noreply,
       assign(socket, confirm_close: true, qualifier_search: "", qualifier_candidates: [])}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to close this stage.")}
    end
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_close", _params, socket),
    do:
      {:noreply,
       assign(socket, confirm_close: false, qualifier_search: "", qualifier_candidates: [])}

  # Lets the admin drop a name the automatic top-N/best-of-rest suggestion
  # included — e.g. a reason the system can't see (DQ, withdrawal).
  def handle_event("remove_qualifier", %{"id" => id}, socket) do
    qualifiers = Enum.reject(socket.assigns.qualifiers, &(&1.participant_id == id))
    {:noreply, assign(socket, :qualifiers, qualifiers)}
  end

  def handle_event("search_qualifier_candidate", %{"query" => query}, socket) do
    candidates =
      if String.trim(query) == "" do
        []
      else
        %{stage: stage, category: category} = socket.assigns

        stage.id
        |> Competitions.search_eligible_qualifiers(category, draw_scope(socket.assigns), query)
        |> Enum.reject(fn c ->
          Enum.any?(socket.assigns.qualifiers, &(&1.participant_id == c.participation.id))
        end)
      end

    {:noreply, assign(socket, qualifier_search: query, qualifier_candidates: candidates)}
  end

  # Lets the admin add someone the automatic suggestion left out — most
  # notably, filling a slot a dead group (nobody played) left empty, or a
  # qualifier the admin knows played but whose result isn't recorded yet
  # (`candidate.played?` is `false` then — see `Competitions.close_group_stage/5`).
  def handle_event("add_qualifier", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.qualifier_candidates, &(&1.participation.id == id)) do
      nil ->
        {:noreply, socket}

      candidate ->
        row = %{
          participant_id: candidate.participation.id,
          name: participant_name(candidate.participation),
          played?: candidate.played?
        }

        {:noreply,
         assign(socket,
           qualifiers: socket.assigns.qualifiers ++ [row],
           qualifier_search: "",
           qualifier_candidates: []
         )}
    end
  end

  def handle_event("close_stage", _params, socket) do
    if socket.assigns.can_close_stage? do
      ids = Enum.map(socket.assigns.qualifiers, & &1.participant_id)

      case Competitions.close_group_stage(
             socket.assigns.stage.id,
             socket.assigns.category,
             draw_scope(socket.assigns),
             socket.assigns.current_admin,
             ids
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:confirm_close, false)
           |> advance_to_next_stage_view()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not close stage: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to close this stage.")}
    end
  end

  # Lets a TD force this venue's groups into "final" before the stage
  # deadline (e.g. every match was played but results weren't entered in
  # time) — see `Competitions.mark_venue_ready_early/4`.
  def handle_event("toggle_venue_ready_early", _params, socket) do
    %{stage: stage, venue: venue, category: category, current_admin: admin} = socket.assigns

    if socket.assigns.can_close_stage? and venue do
      result =
        if socket.assigns.venue_ready_early? do
          Competitions.unmark_venue_ready_early(stage.id, venue.id, category, admin)
        else
          Competitions.mark_venue_ready_early(stage.id, venue.id, category, admin)
        end

      case result do
        {:ok, _} ->
          {:noreply,
           socket |> load_result_sheets_and_readiness() |> load_gr_standings_if_needed()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Couldn't update: #{format_error(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  def handle_event("upload_result_sheet", _params, socket) do
    %{stage: stage, venue: venue, current_admin: admin} = socket.assigns

    if socket.assigns.can_upload_result_sheets? and venue do
      results =
        consume_uploaded_entries(socket, :result_sheet, fn %{path: path}, entry ->
          store_result_sheet_entry(stage, venue, admin, path, entry)
        end)

      socket =
        case results do
          [{:ok, _result_sheet}] ->
            socket
            |> put_flash(:info, "Result sheet uploaded.")
            |> load_result_sheets_and_readiness()

          [{:error, :unsupported_content_type}] ->
            put_flash(socket, :error, "Only JPG, JPEG or PDF files are accepted.")

          [{:error, reason}] ->
            put_flash(socket, :error, "Couldn't upload: #{format_error(reason)}")

          [] ->
            put_flash(socket, :error, "Choose a file first.")
        end

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to upload result sheets.")}
    end
  end

  def handle_event("advance_all_entrants", _params, socket) do
    if socket.assigns.can_close_stage? do
      case Competitions.advance_all_entrants(
             socket.assigns.stage.id,
             socket.assigns.category,
             draw_scope(socket.assigns),
             socket.assigns.current_admin
           ) do
        {:ok, _} ->
          {:noreply, advance_to_next_stage_view(socket)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not advance everyone: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to advance participants.")}
    end
  end

  def handle_event("open_bulk_add", _params, socket) do
    {:noreply, assign(socket, bulk_add_open?: true, bulk_add_result: nil)}
  end

  def handle_event("cancel_bulk_add", _params, socket) do
    {:noreply,
     assign(socket,
       bulk_add_open?: false,
       bulk_add_result: nil,
       bulk_add_form: to_form(%{}, as: :bulk_add)
     )}
  end

  # Catch-up path for players a venue never got around to manually
  # advancing out of Grassroots — pastes a list of usernames and advances
  # each one straight into this region's Regional stage, best-effort (one
  # bad username doesn't block the rest of the batch). See
  # `Competitions.bulk_advance_to_regional/3` for the validation rules.
  def handle_event("submit_bulk_add", %{"bulk_add" => %{"usernames" => text}}, socket) do
    if socket.assigns.can_close_stage? do
      usernames = String.split(text, ["\n", ",", "\r"], trim: true)

      case Competitions.bulk_advance_to_regional(
             usernames,
             socket.assigns.region.id,
             socket.assigns.current_admin
           ) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(bulk_add_result: result, bulk_add_form: to_form(%{}, as: :bulk_add))
           |> load_gr()}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to add participants.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to add participants.")}
    end
  end

  # Opens the match-entry slide-over in place of navigating to
  # `/admin/matches/:id` — an admin scoring results out of a published
  # group's fixture list stays on the Groups page throughout.
  def handle_event("open_match_entry", %{"id" => fixture_id}, socket) do
    {:noreply, assign(socket, :selected_fixture_id, fixture_id)}
  end

  def handle_event("close_match_entry", _params, socket) do
    {:noreply, assign(socket, :selected_fixture_id, nil)}
  end

  # `MatchEntryComponent` sends this after any state-changing action
  # (record/verify/postpone/resume/walkover) — refresh the group cards'
  # fixture statuses and progress counts to match.
  def handle_info({:match_entry_updated, _fixture_id}, socket) do
    {:noreply, load_gr(socket)}
  end

  defp store_result_sheet_entry(stage, venue, admin, path, entry) do
    body = File.read!(path)

    case Competitions.upload_result_sheet(
           stage,
           venue,
           admin,
           body,
           entry.client_type,
           entry.client_name
         ) do
      {:ok, result_sheet} -> {:ok, {:ok, result_sheet}}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  # After a successful close, the admin's next move is almost always to go
  # draw the stage they just fed — so land them there directly (same
  # venue/region/category carried over) instead of leaving them staring at
  # the same "Close stage" screen, now with nothing left to confirm.
  defp advance_to_next_stage_view(socket) do
    case Competitions.next_stage(socket.assigns.stage) do
      nil ->
        socket |> put_flash(:info, "Qualifiers advanced.") |> load_gr_standings()

      next_stage ->
        categories = categories_for_stage(next_stage)

        category =
          if socket.assigns.category in categories,
            do: socket.assigns.category,
            else: List.first(categories)

        prior_venue = socket.assigns[:venue]

        socket
        |> put_flash(:info, "Qualifiers advanced to #{next_stage.name}.")
        |> assign(stage: next_stage, categories: categories, category: category)
        |> load_venues()
        |> keep_venue_if_valid(prior_venue)
        |> load_scope()
    end
  end

  defp keep_venue_if_valid(socket, %{id: id} = venue) do
    if Enum.any?(socket.assigns.venues, &(&1.id == id)),
      do: assign(socket, :venue, venue),
      else: socket
  end

  defp keep_venue_if_valid(socket, _venue), do: socket

  ## Loading

  # Takes an assigns map, not a socket — deliberately, so the exact same
  # function works both from `handle_event`/loaders (`grassroots?(socket.assigns)`)
  # and directly from the template (`auto_draw_eligible?(assigns)`), which
  # only ever sees `assigns`, never `socket`.
  defp grassroots?(assigns), do: Stage.grassroots?(assigns.stage)

  defp regional?(assigns), do: assigns.stage.name == "Regional"

  # The formula-driven draw engine applies to: Grassroots Individual Male
  # with a venue selected (venue-scoped), or any Regional Individual/Team
  # category (region-scoped) — see the moduledoc.
  defp auto_draw_eligible?(assigns) do
    cond do
      grassroots?(assigns) -> assigns.category == "male" and !!assigns.venue
      regional?(assigns) -> assigns.category in ~w(male female team)
      true -> false
    end
  end

  defp everyone_qualifies?(stage, category, scope) do
    config = Competitions.get_or_create_group_config(stage.id, category)
    count = Competitions.draw_entrant_count(stage.id, scope, category)
    count > 0 and count <= config.advancer_count
  end

  # `{:venue_id, id} | {:region_id, id}` for whichever scope dimension
  # applies to the current stage selection — mirrors
  # `Competitions.draw_scope/1`, just derived from the live `assigns` map
  # instead of a persisted `Draw`.
  defp draw_scope(assigns) do
    cond do
      grassroots?(assigns) and assigns.venue -> {:venue_id, assigns.venue.id}
      regional?(assigns) -> {:region_id, assigns.region.id}
      true -> nil
    end
  end

  defp scope_attrs({:venue_id, id}), do: %{venue_id: id}
  defp scope_attrs({:region_id, id}), do: %{region_id: id}

  defp categories_for_stage(%Stage{} = stage) do
    if Stage.grassroots?(stage), do: ~w(male), else: @categories
  end

  defp load_venues(socket) do
    if socket.assigns.venue_rep? do
      assign(socket,
        venues: List.wrap(socket.assigns.current_admin.venue),
        venue: socket.assigns.current_admin.venue
      )
    else
      if grassroots?(socket.assigns) do
        venues = Venues.list_active_for_region(socket.assigns.region.id)
        assign(socket, venues: venues, venue: List.first(venues))
      else
        assign(socket, venues: [], venue: nil)
      end
    end
  end

  # Single entry point after any scope change (stage/region/venue/category) —
  # routes to whichever of the two experiences applies.
  defp load_scope(socket) do
    socket =
      assign(socket,
        gr_view: :groups,
        standings_view: :per_group,
        proposal: nil,
        group_count: nil,
        sizes: nil,
        redraw_open: false,
        redraw_reason: "",
        open_group_ids: MapSet.new(),
        gr_open_group_id: nil,
        gr_selected_member_id: nil,
        confirm_close: false,
        tie_resolution: nil,
        bulk_add_open?: false,
        bulk_add_form: to_form(%{}, as: :bulk_add),
        bulk_add_result: nil,
        selected_fixture_id: nil
      )
      |> load_result_sheets_and_readiness()

    if auto_draw_eligible?(socket.assigns),
      do: load_gr(socket),
      else: socket |> load_groups() |> load_unassigned()
  end

  # Both the "mark venue ready early" override and the result-sheet
  # uploads below are venue+stage+category scoped (spec 012) — only
  # meaningful for Grassroots, where groups are venue-scoped at all.
  defp load_result_sheets_and_readiness(socket) do
    %{stage: stage, category: category, venue: venue} = socket.assigns

    if grassroots?(socket.assigns) and venue do
      assign(socket,
        result_sheets: Competitions.list_result_sheets(stage.id, venue.id),
        venue_ready_early?:
          Competitions.venue_marked_ready_early?(stage.id, category, {:venue_id, venue.id})
      )
    else
      assign(socket, result_sheets: [], venue_ready_early?: false)
    end
  end

  defp load_gr(socket) do
    %{stage: stage, category: category} = socket.assigns
    scope = draw_scope(socket.assigns)
    draw = Competitions.latest_draw(stage.id, scope, category)
    dealt? = draw && draw.state != "draft"
    groups = if(dealt?, do: Competitions.list_groups_for_draw(draw.id), else: [])
    draw_pending? = is_nil(draw) or draw.state == "draft"

    # Once the entrant pool is this small, a draw has nothing left to
    # decide — everyone in it qualifies regardless of result (see
    # `Competitions.advance_all_entrants/4`). Only worth computing before a
    # draw exists; once one's dealt, the groups already own that decision.
    socket =
      assign(socket,
        everyone_qualifies?: draw_pending? and everyone_qualifies?(stage, category, scope),
        gr_next_stage: draw_pending? && Competitions.next_stage(stage)
      )

    # Every group's fixtures, loaded once here rather than per-card in the
    # template — needed for the always-visible per-member progress and
    # per-card "N/M played" line (design: `done+'/'+total+' played'`), not
    # just whichever card's fixtures panel happens to be expanded. Only
    # meaningful once published (FR-008 generates fixtures on that
    # transition; before it there's nothing to fetch). One batched query
    # for every group at once (`list_fixtures_for_groups/1`), not one
    # query per group — a published Regional draw means 15-30+ groups, and
    # this reload fires on every single result/walkover/postpone (see
    # `handle_info({:match_entry_updated, ...})`), so the per-group version
    # here would mean dozens of round trips on every score entered during
    # a live draw.
    group_fixtures =
      if draw && draw.state == "published" do
        Competitions.list_fixtures_for_groups(Enum.map(groups, & &1.id))
      else
        %{}
      end

    socket = assign(socket, draw: draw, groups: groups, group_fixtures: group_fixtures)

    if socket.assigns.gr_view == :standings, do: load_gr_standings(socket), else: socket
  end

  defp load_gr_standings_if_needed(socket) do
    if socket.assigns.gr_view == :standings and auto_draw_eligible?(socket.assigns),
      do: load_gr_standings(socket),
      else: socket
  end

  defp load_gr_standings(socket) do
    %{stage: stage, category: category, groups: groups} = socket.assigns
    config = Competitions.get_or_create_group_config(stage.id, category)
    scope = draw_scope(socket.assigns)
    final_groups_in_scope = Competitions.final_groups(stage.id, category, scope)
    final_group_ids = MapSet.new(final_groups_in_scope, & &1.id)

    all_groups = Enum.uniq_by(groups ++ final_groups_in_scope, & &1.id)
    all_group_ids = Enum.map(all_groups, & &1.id)

    # One query for every group this render needs "who actually played"
    # for, instead of one query per group repeated across the per-card
    # tables and the qualifier suggestion below — a venue's worth of
    # groups otherwise means a dozen-plus near-identical round trips on
    # every single standings render.
    played_by_group = Competitions.played_participant_ids_by_group(all_group_ids)

    # Same idea, for the standings themselves — one batched match/membership
    # query for every group instead of two per group. At Regional's
    # 15-30+-groups-per-region scale, the per-group version this replaced
    # turned switching to the Standings tab into 60-100+ round trips.
    standings_by_group = Competitions.grassroots_group_standings_by_group(all_groups, stage)

    tables =
      Enum.map(groups, fn group ->
        rows = standings_by_group |> Map.get(group.id, []) |> name_rows()
        final? = MapSet.member?(final_group_ids, group.id)

        top =
          if final? do
            played_ids = Map.get(played_by_group, group.id, MapSet.new())

            rows
            |> Enum.filter(&MapSet.member?(played_ids, &1.participant_id))
            |> Enum.take(config.advancer_count)
          else
            []
          end

        %{group: group, rows: rows, final?: final?, top: top}
      end)

    best_rest =
      stage.id |> Competitions.best_of_rest_qualifiers(category, scope) |> name_rows()

    all_top =
      final_groups_in_scope
      |> Enum.flat_map(fn g ->
        played_ids = Map.get(played_by_group, g.id, MapSet.new())

        standings_by_group
        |> Map.get(g.id, [])
        |> Enum.filter(&MapSet.member?(played_ids, &1.participant_id))
        |> Enum.take(config.advancer_count)
      end)
      |> name_rows()

    qualifiers =
      Enum.uniq_by(all_top ++ best_rest, & &1.participant_id)
      |> reject_already_advanced(stage.id)

    names = tables |> Enum.flat_map(& &1.rows) |> Map.new(&{&1.participant_id, &1.name})

    assign(socket,
      standings_tables: tables,
      any_final_group?: final_groups_in_scope != [],
      overall_rows: overall_rows(tables),
      standings_names: names,
      config: config,
      best_rest_qualifiers: best_rest,
      qualifiers: qualifiers
    )
  end

  # Closing is scoped to this venue/region, but re-selecting the same
  # scope after a prior close would otherwise recompute the exact same
  # qualifier list from group standings. Excluding anyone whose
  # `StageParticipation` no longer sits at this stage is what makes
  # "Close stage & advance qualifiers" disappear once there's truly
  # nothing left to advance here, instead of reappearing with the same
  # names.
  defp reject_already_advanced(rows, stage_id) do
    ids = Enum.map(rows, & &1.participant_id)

    current_stage_ids =
      from(sp in StageParticipation, where: sp.id in ^ids, select: {sp.id, sp.stage_id})
      |> Repo.all()
      |> Map.new()

    Enum.filter(rows, &(Map.get(current_stage_ids, &1.participant_id) == stage_id))
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

  # Cross-group overview for the "Venue overall" standings toggle — ranked
  # by points (then frame difference, then wins) across every group at this
  # venue. This is a convenience view only: official qualification is
  # decided per group above, since group sizes and schedules differ.
  defp overall_rows(tables) do
    tables
    |> Enum.flat_map(fn table ->
      Enum.map(table.rows, &Map.merge(&1, %{group_name: table.group.name, tied: false}))
    end)
    |> Enum.sort_by(&{-&1.points, -&1.frame_diff, -&1.wins}, :asc)
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

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
    "#{assigns.stage.name} · #{scope_name(assigns)} · #{category_label(assigns.category)}"
  end

  defp scope_name(assigns) do
    if Stage.grassroots?(assigns.stage) && assigns.venue,
      do: assigns.venue.name,
      else: assigns.region.name
  end

  defp category_label("male"), do: "Individual Male"
  defp category_label("female"), do: "Individual Female"
  defp category_label("team"), do: "Teams"

  defp bulk_add_error_label(:player_not_found), do: "no player with that username"
  defp bulk_add_error_label(:not_in_grassroots), do: "not currently in Grassroots"
  defp bulk_add_error_label(:wrong_region), do: "registered in a different region"
  defp bulk_add_error_label(:registration_closed), do: "registration is closed for them"
  defp bulk_add_error_label(:capacity_exceeded), do: "Regional is at capacity"
  defp bulk_add_error_label(reason), do: inspect(reason)

  defp draw_step_index(nil), do: 0

  defp draw_step_index(%Draw{state: state}),
    do: Enum.find_index(@draw_states, &(&1 == state)) || 0

  defp draw_step_label(index), do: Enum.at(@draw_states, index) |> String.capitalize()

  defp draw_state_label(state), do: String.capitalize(state)

  defp draw_state_pill_class("published"), do: "bg-ink-950 text-white"
  defp draw_state_pill_class(_state), do: "bg-ink-100 text-ink-700"

  defp gr_fixtures_for(group_fixtures, group), do: Map.get(group_fixtures, group.id, [])

  # Fixtures optionally narrowed to one member's matches (design's
  # `grMemberSel` filter, cleared via a "Clear" link once set).
  defp filtered_gr_fixtures(fixtures, nil), do: fixtures

  defp filtered_gr_fixtures(fixtures, member_id) do
    Enum.filter(fixtures, &(&1.participant_a_id == member_id or &1.participant_b_id == member_id))
  end

  defp gr_fixtures_filter_label(nil, _members), do: "All fixtures"

  defp gr_fixtures_filter_label(member_id, members) do
    case Enum.find(members, &(&1.stage_participation_id == member_id)) do
      nil -> "All fixtures"
      membership -> "Showing #{participant_name(membership.stage_participation)}’s fixtures"
    end
  end

  defp ngettext_group(1), do: "group"
  defp ngettext_group(_count), do: "groups"

  defp fixture_progress(fixtures),
    do: {Enum.count(fixtures, &actually_played?/1), length(fixtures)}

  defp member_progress(fixtures, participation_id) do
    played =
      Enum.count(fixtures, fn f ->
        actually_played?(f) and
          (f.participant_a_id == participation_id or f.participant_b_id == participation_id)
      end)

    total =
      Enum.count(fixtures, fn f ->
        f.participant_a_id == participation_id or f.participant_b_id == participation_id
      end)

    "#{played}/#{total}"
  end

  # A verified result, or a real (single) walkover. Excludes a "double"
  # walkover — GrassrootsDeadlineWorker's auto-closure of a fixture nobody
  # played before the stage deadline — which must not count as played.
  defp actually_played?(%{status: "verified"}), do: true
  defp actually_played?(%{status: "walkover", walkover_kind: "double"}), do: false
  defp actually_played?(%{status: "walkover"}), do: true
  defp actually_played?(_fixture), do: false

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
  defp format_error(:redraw_limit_reached), do: "the three pre-approval redraws have been used"
  defp format_error(:invalid_transition), do: "reshuffling is only available before approval"
  defp format_error(:reason_required), do: "a reason is required"
  defp format_error(reason), do: inspect(reason)

  defp upload_error_message(:too_large), do: "File is too large (max 15MB)."
  defp upload_error_message(:not_accepted), do: "Only JPG, JPEG or PDF files are accepted."
  defp upload_error_message(:too_many_files), do: "Only one file at a time."
  defp upload_error_message(reason), do: inspect(reason)

  # Matches CuevolutionWeb.PlayerComponents' @stage_styles palette (the
  # actual app design system — gray/Kenya-Green/Kenya-Red/ink-950), not the
  # Grassroots/Regional colors in the reference mockup's latest revision.
  defp stage_tab_active_class("Grassroots"), do: "border-ink-500 bg-ink-100 text-ink-700"

  defp stage_tab_active_class("Grassroots Round 2"),
    do: "border-amber-500 bg-amber-100 text-amber-700"

  defp stage_tab_active_class("Regional"), do: "border-green-500 bg-green-100 text-green-700"
  defp stage_tab_active_class(_stage), do: "border-red-500 bg-red-50 text-red-700"
end
