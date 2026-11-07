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
  alias CuevolutionWeb.BracketComponents

  @categories ~w(male female team)
  @draw_states ~w(draft previewed approved published)

  def mount(_params, _session, socket) do
    current_admin = Repo.preload(socket.assigns.current_admin, venue: :region)
    venue_rep? = current_admin.role == "venue_representative"

    # Circuit is a knockout stage, not round-robin, but it belongs on the same
    # screen: the tournament director already comes here to draw every other
    # stage, and a separate page for one stage is a worse habit to learn than
    # one extra tab.
    stages =
      Competitions.list_stages()
      |> Enum.filter(&(Stage.round_robin?(&1) or &1.name == "Circuit"))

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
       can_approve_results?: Admin.can?(current_admin, :approve_results),
       circuit_editing: false,
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
     |> assign(venues: [])}
  end

  @doc """
  The selected stage, category, region and venue live in the query string, so
  a refresh — or a shared link, or the browser's back button — lands back on
  the tab you were looking at instead of resetting to Grassroots.

  Anything missing or no longer valid falls back to the first option, which is
  also what an unadorned `/admin/groups` gets.
  """
  def handle_params(params, _uri, socket) do
    stage = find_stage(socket.assigns.stages, params["stage"]) || socket.assigns.stage
    categories = categories_for_stage(stage)

    category =
      if params["category"] in categories,
        do: params["category"],
        else: List.first(categories)

    region = find_by_id(socket.assigns.regions, params["region"]) || socket.assigns.region

    socket =
      socket
      |> assign(stage: stage, categories: categories, category: category, region: region)
      |> load_venues()

    # The venue list depends on the region, so it can only be resolved once
    # `load_venues/1` has run for the region we just settled on.
    venue = find_by_id(socket.assigns.venues, params["venue"]) || socket.assigns.venue

    {:noreply, socket |> assign(venue: venue) |> load_scope()}
  end

  defp find_stage(_stages, nil), do: nil
  defp find_stage(stages, name), do: Enum.find(stages, &(&1.name == name))

  defp find_by_id(_collection, nil), do: nil
  defp find_by_id(collection, id), do: Enum.find(collection, &(&1.id == id))

  # Every scope change goes through the URL rather than straight into assigns,
  # which is what makes the selection survive a reload.
  defp patch_scope(socket, overrides) do
    params =
      %{
        "stage" => socket.assigns.stage.name,
        "category" => socket.assigns.category,
        "region" => socket.assigns.region && socket.assigns.region.id,
        "venue" => socket.assigns.venue && socket.assigns.venue.id
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    push_patch(socket, to: ~p"/admin/groups?#{params}")
  end

  ## Shared stage/region/venue/category navigation (used by both experiences)

  def handle_event("select_stage", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.stages, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That stage is not available.")}

      stage ->
        # The category and venue are re-resolved in handle_params against the
        # new stage, so a category that stage doesn't run falls back cleanly.
        {:noreply, patch_scope(socket, %{"stage" => stage.name, "venue" => nil})}
    end
  end

  def handle_event("select_region", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.regions, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That region is not available.")}

      region ->
        {:noreply, patch_scope(socket, %{"region" => region.id, "venue" => nil})}
    end
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    if category in socket.assigns.categories,
      do: {:noreply, patch_scope(socket, %{"category" => category})},
      else: {:noreply, put_flash(socket, :error, "That category is not available.")}
  end

  def handle_event("select_venue", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.venues, &(&1.id == id)) do
      nil -> {:noreply, put_flash(socket, :error, "That venue is not available.")}
      venue -> {:noreply, patch_scope(socket, %{"venue" => venue.id})}
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

  # ---------------------------------------------------------------- circuit
  #
  # The Circuit stage is a double-elimination bracket rather than groups, so
  # it gets its own events and its own section of the template. Everything
  # else on this screen — stage tabs, category tabs — is shared.

  def handle_event("draw_circuit", _params, socket) do
    %{stage: stage, category: category, current_admin: admin} = socket.assigns

    case Competitions.draw_circuit_bracket(stage.id, category, admin) do
      {:ok, %{entrants: entrants, seed: seed}} ->
        {:noreply,
         socket
         |> load_scope()
         |> assign(circuit_notice: "Draw made for #{entrants}. Draw reference #{seed}.")}

      {:error, :too_few_entrants} ->
        {:noreply, put_flash(socket, :error, "Not enough entrants to make a draw.")}

      {:error, :bracket_exists} ->
        {:noreply,
         socket |> load_scope() |> put_flash(:error, "This draw has already been made.")}

      {:error, :match_ids_taken} ->
        {:noreply,
         put_flash(socket, :error, "Another circuit has already used this match numbering.")}

      {:error, :format_not_supported} ->
        {:noreply,
         put_flash(socket, :error, "The team event is played as groups, not a bracket.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can make the draw.")}
    end
  end

  def handle_event("redeal_circuit_draw", _params, socket) do
    %{stage: stage, category: category, current_admin: admin} = socket.assigns

    case Competitions.reshuffle_circuit_draw(stage.id, category, admin) do
      {:ok, %{entrants: entrants, seed: seed, redraw_count: count}} ->
        {:noreply,
         socket
         |> load_scope()
         |> assign(
           circuit_notice:
             "Re-dealt #{count} of 3 — #{entrants} drawn again. Draw reference #{seed}."
         )}

      {:error, :redraw_limit_reached} ->
        {:noreply, put_flash(socket, :error, "This draw has already been re-dealt three times.")}

      {:error, :results_recorded} ->
        {:noreply,
         socket
         |> load_scope()
         |> put_flash(
           :error,
           "Results have already been recorded — this draw cannot be re-dealt."
         )}

      {:error, :no_bracket} ->
        {:noreply, load_scope(socket)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can re-deal the draw.")}
    end
  end

  def handle_event("circuit_view", %{"view" => view}, socket) when view in ~w(chart stage list) do
    {:noreply, assign(socket, circuit_view: String.to_existing_atom(view))}
  end

  def handle_event("circuit_side", %{"side" => side}, socket)
      when side in ~w(winners losers finals) do
    {:noreply, assign(socket, circuit_side: String.to_existing_atom(side))}
  end

  def handle_event("circuit_zoom", %{"zoom" => zoom}, socket) when zoom in ~w(fit 80 100) do
    {:noreply,
     assign(socket, circuit_zoom: if(zoom == "fit", do: :fit, else: String.to_integer(zoom)))}
  end

  def handle_event("circuit_filter", %{"filter" => filter}, socket)
      when filter in ~w(all live next finished) do
    {:noreply, assign(socket, circuit_filter: String.to_existing_atom(filter))}
  end

  def handle_event("schedule_circuit_fixture", %{"slot" => params}, socket) do
    fixture = circuit_fixture(socket.assigns, params["id"])

    case Competitions.schedule_bracket_fixture(fixture, socket.assigns.current_admin, params) do
      {:ok, _} ->
        {:noreply, socket |> load_scope() |> put_flash(:info, "Match time saved.")}

      {:error, :locked} ->
        {:noreply,
         put_flash(socket, :error, "This match has been played — its time can no longer change.")}

      {:error, :invalid_datetime} ->
        {:noreply, put_flash(socket, :error, "That start time is not valid.")}

      {:error, :past_date} ->
        {:noreply, put_flash(socket, :error, "A match cannot be scheduled before today.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You cannot schedule matches.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save that time.")}
    end
  end

  # ------------------------------------------------- Circuit team event (014)

  def handle_event("draw_circuit_teams", _params, socket) do
    stage = socket.assigns.stage

    case Competitions.draw_circuit_team_groups(stage.id, socket.assigns.current_admin) do
      {:ok, %{groups: groups}} ->
        {:noreply,
         socket
         |> load_scope()
         |> assign(circuit_notice: "Drawn — #{length(groups)} groups.")}

      {:error, :already_drawn} ->
        {:noreply, put_flash(socket, :error, "The team draw has already been made.")}

      {:error, :below_minimum} ->
        {:noreply,
         put_flash(socket, :error, "At least 10 teams are needed to make the team draw.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can make the draw.")}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not make the team draw.")}
    end
  end

  def handle_event("redraw_circuit_teams", _params, socket) do
    stage = socket.assigns.stage

    case Competitions.redraw_circuit_team_groups(stage.id, socket.assigns.current_admin) do
      {:ok, _} ->
        {:noreply, socket |> load_scope() |> assign(circuit_notice: "Dealt again.")}

      {:error, :redraw_limit} ->
        {:noreply, put_flash(socket, :error, "The team draw has been dealt the maximum 3 times.")}

      {:error, :results_exist} ->
        {:noreply,
         put_flash(socket, :error, "A result has been recorded — the draw can no longer change.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can re-deal the draw.")}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not deal the team draw again.")}
    end
  end

  def handle_event("reset_circuit_teams", _params, socket) do
    stage = socket.assigns.stage

    case Competitions.reset_circuit_team_draw(stage.id, socket.assigns.current_admin) do
      :ok ->
        {:noreply, socket |> load_scope() |> assign(circuit_notice: "Team draw cleared.")}

      {:error, :results_recorded} ->
        {:noreply,
         put_flash(socket, :error, "Results have been recorded — the draw cannot be cleared.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can clear the draw.")}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not clear the team draw.")}
    end
  end

  def handle_event("circuit_team_view", %{"view" => view}, socket)
      when view in ~w(table fixtures) do
    {:noreply, assign(socket, circuit_team_view: String.to_existing_atom(view))}
  end

  def handle_event("circuit_team_round", %{"round" => round}, socket) do
    {:noreply, assign(socket, circuit_team_round: String.to_integer(round))}
  end

  def handle_event("select_circuit_fixture", %{"id" => id}, socket) do
    {:noreply,
     assign(socket,
       circuit_selected: id,
       circuit_selected_fixture: circuit_fixture(socket.assigns, id),
       circuit_editing: false
     )}
  end

  def handle_event("edit_circuit_result", _params, socket) do
    {:noreply, assign(socket, circuit_editing: true)}
  end

  def handle_event("cancel_circuit_edit", _params, socket) do
    {:noreply, assign(socket, circuit_editing: false)}
  end

  def handle_event("correct_circuit_result", %{"correction" => params}, socket) do
    fixture = circuit_fixture(socket.assigns, params["id"])

    attrs = %{
      "winner_participation_id" => params["winner"],
      "score" => %{
        "a" => to_frame_count(params["frames_a"]),
        "b" => to_frame_count(params["frames_b"])
      }
    }

    case Competitions.correct_fixture_result(fixture, socket.assigns.current_admin, attrs) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(circuit_editing: false)
         |> load_scope()
         |> put_flash(:info, "Result corrected. The previous score is in the audit log.")}

      {:error, :downstream_played} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A later match has already been played, so the winner can no longer change. " <>
             "Correct the later match first, or change only the score."
         )}

      {:error, :not_recorded} ->
        {:noreply, put_flash(socket, :error, "That match has no result to correct.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only a tournament director can correct a result.")}

      {:error, :results_recording_closed} ->
        {:noreply, put_flash(socket, :error, "Result recording is closed.")}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not correct that result.")}
    end
  end

  def handle_event("close_circuit_fixture", _params, socket) do
    {:noreply,
     assign(socket,
       circuit_selected: nil,
       circuit_selected_fixture: nil,
       circuit_editing: false
     )}
  end

  # The hot path while matches are being played: one tap per frame, no form.
  def handle_event("circuit_frame", %{"id" => id, "side" => side, "delta" => delta}, socket) do
    fixture = circuit_fixture(socket.assigns, id)
    current = fixture.live_score || %{"a" => 0, "b" => 0}

    score =
      current
      |> Map.update(side, 0, &(&1 + String.to_integer(delta)))
      |> Map.put_new("a", 0)
      |> Map.put_new("b", 0)

    case Competitions.update_live_score(fixture, socket.assigns.current_admin, score) do
      {:ok, _} ->
        {:noreply, load_scope(socket)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You cannot record results.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save that frame.")}
    end
  end

  def handle_event("finish_circuit_fixture", %{"id" => id, "winner" => winner_id}, socket) do
    fixture = circuit_fixture(socket.assigns, id)

    attrs = %{
      "winner_participation_id" => winner_id,
      "score" => fixture.live_score || %{"a" => 0, "b" => 0}
    }

    case Competitions.record_result(fixture, socket.assigns.current_admin, attrs) do
      {:ok, _result} ->
        {:noreply, socket |> load_scope() |> assign(circuit_selected: nil)}

      {:error, :results_recording_closed} ->
        {:noreply, put_flash(socket, :error, "Result recording is closed.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You cannot record results.")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        message =
          if Keyword.has_key?(errors, :fixture_id),
            do: "This match has already been recorded.",
            else: "Could not record that result."

        {:noreply, socket |> load_scope() |> put_flash(:error, message)}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not record that result.")}
    end
  end

  # Each fixture comes back with its round attached, because every scoring
  # decision needs that round's race length.
  defp circuit_fixture(%{circuit_bracket: %{rounds: rounds}}, id) do
    team_fixture(rounds, id)
  end

  # The team event's fixtures live in groups rather than a bracket, which is
  # the only difference the scoring handlers need to know about.
  defp circuit_fixture(%{circuit_team_rounds: rounds}, id) when is_list(rounds) do
    team_fixture(rounds, id)
  end

  defp circuit_fixture(_assigns, _id), do: nil

  # `MatchEntryComponent` sends this after any state-changing action
  # (record/verify/postpone/resume/walkover) — refresh the group cards'
  # fixture statuses and progress counts to match.
  def handle_info({:match_entry_updated, _fixture_id}, socket) do
    {:noreply, load_gr(socket)}
  end

  # Any recorded result on the Circuit bracket, from here or another admin.
  def handle_info({:bracket_updated, _bracket_id}, socket), do: {:noreply, load_scope(socket)}

  # The same, for the Circuit team event: a draw, a re-deal or a frame.
  def handle_info({:circuit_teams_updated, _stage_id}, socket),
    do: {:noreply, load_scope(socket)}

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
  # ---- slot display ------------------------------------------------------

  defp slot_time(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> nil
      start -> Calendar.strftime(start, "%H:%M")
    end
  end

  defp slot_date_value(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> Date.to_iso8601(Competitions.today_in_eat())
      start -> start |> DateTime.to_date() |> Date.to_iso8601()
    end
  end

  # The start time as it shows on a card, local time, e.g. "19:31".
  defp slot_label(fixture), do: slot_time(fixture)

  defp slot_day_label(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> nil
      start -> Calendar.strftime(start, "%a %-d %b, %H:%M")
    end
  end

  # ---- presentation ------------------------------------------------------
  #
  # Matches are numbered M1..Mn across the whole bracket in play order, the way
  # a printed draw sheet numbers them, rather than by their internal
  # round-and-slot code. Built once per render and handed to the template.

  defp circuit_match_numbers(rounds) do
    rounds
    |> Enum.sort_by(& &1.sequence)
    |> Enum.flat_map(fn round -> Enum.sort_by(round.fixtures, & &1.slot) end)
    |> Enum.with_index(1)
    |> Map.new(fn {fixture, n} -> {fixture.id, "M#{n}"} end)
  end

  defp match_number(numbers, %{id: id}), do: Map.get(numbers, id, "—")

  # Where this match's loser goes — the thing that makes a double-elimination
  # sheet readable, and the reason fixtures carry a loser route at all.
  defp loser_destination(_numbers, %{loser_to_fixture_id: nil}), do: "Loser is out"

  defp loser_destination(numbers, %{loser_to_fixture_id: id}) do
    case Map.get(numbers, id) do
      nil -> "Loser is out"
      code -> "Loser to #{code}"
    end
  end

  defp circuit_counts(rounds) do
    fixtures = Enum.flat_map(rounds, & &1.fixtures)

    %{
      all: length(fixtures),
      live: Enum.count(fixtures, &(fixture_state(&1) == :live)),
      next: Enum.count(fixtures, &(fixture_state(&1) == :ready)),
      finished: Enum.count(fixtures, &(fixture_state(&1) in [:done, :walkover]))
    }
  end

  defp filter_fixtures(fixtures, :all), do: fixtures
  defp filter_fixtures(fixtures, :live), do: Enum.filter(fixtures, &(fixture_state(&1) == :live))
  defp filter_fixtures(fixtures, :next), do: Enum.filter(fixtures, &(fixture_state(&1) == :ready))

  defp filter_fixtures(fixtures, :finished),
    do: Enum.filter(fixtures, &(fixture_state(&1) in [:done, :walkover]))

  defp zoom_style(:fit), do: nil
  defp zoom_style(percent), do: "zoom:#{percent / 100}"

  defp round_progress(round) do
    played = Enum.count(round.fixtures, &(fixture_state(&1) in [:done, :walkover]))
    live = Enum.count(round.fixtures, &(fixture_state(&1) == :live))
    total = length(round.fixtures)

    base = "#{played} of #{total} played"
    if live > 0, do: base <> " · #{live} live", else: base
  end

  defp status_label(:done), do: "Final"
  defp status_label(:walkover), do: "Walkover"
  defp status_label(:live), do: "Live"
  defp status_label(:ready), do: "Up next"
  defp status_label(:waiting), do: "Waiting"

  # Lanes with their geometry already worked out, so the template only reads.
  # Shared with the public chart (BracketComponents), knockout folding and all.
  defp circuit_lane_data(rounds) do
    rounds
    |> circuit_lanes()
    |> Enum.reject(fn {_title, _side, lane_rounds} -> lane_rounds == [] end)
    |> Enum.map(fn {title, side, lane_rounds} ->
      BracketComponents.build_lane(title, side, lane_rounds, :fixtures)
    end)
  end

  # The "Finals" tab is the knockout lane.
  defp lane_side(:winners), do: "winners"
  defp lane_side(:losers), do: "losers"
  defp lane_side(:finals), do: "knockout"

  defp circuit_lanes(rounds) do
    [
      {"Winners' side", "winners", Enum.filter(rounds, &(&1.bracket_side == "winners"))},
      {"Losers' side", "losers", Enum.filter(rounds, &(&1.bracket_side == "losers"))},
      {"Knockout", "knockout", Enum.filter(rounds, &(&1.bracket_side == "knockout"))}
    ]
  end

  @doc """
  True when this side of the card holds whoever arrived from the winners'
  bracket — slot A of a crossover card, and slot A of the first knockout
  round, where the unbeaten player meets a survivor.

  Shaded so the chart answers "who came down from the top half" without
  anyone having to trace the lines back.
  """
  def from_winners_side?(round, side, first_knockout_sequence) do
    side == "a" and
      ((round.bracket_side == "losers" and crossover?(round)) or
         (round.bracket_side == "knockout" and round.sequence == first_knockout_sequence))
  end

  # The crossover is the second losers' round — the only one fed from above.
  defp crossover?(%{name: name}), do: String.ends_with?(name, "Round 2")

  @doc "Sequence of the first knockout round, where the two halves meet."
  def first_knockout_sequence(rounds) do
    rounds
    |> Enum.filter(&(&1.bracket_side == "knockout"))
    |> Enum.map(& &1.sequence)
    |> Enum.min(fn -> -1 end)
  end

  defp fixture_score(%{result: %{score: %{} = final}}, side), do: Map.get(final, side)
  defp fixture_score(%{live_score: %{} = live}, side), do: Map.get(live, side)
  defp fixture_score(_fixture, _side), do: nil

  defp fixture_winner?(%{result: %{winner_participation_id: id}} = f, "a") when is_binary(id),
    do: f.participant_a_id == id

  defp fixture_winner?(%{result: %{winner_participation_id: id}} = f, "b") when is_binary(id),
    do: f.participant_b_id == id

  defp fixture_winner?(_fixture, _side), do: false

  defp fixture_state(%{status: s}) when s in ["completed", "verified"], do: :done
  defp fixture_state(%{status: "live"}), do: :live
  defp fixture_state(%{status: "walkover"}), do: :walkover
  defp fixture_state(%{participant_a_id: nil}), do: :waiting
  defp fixture_state(%{participant_b_id: nil}), do: :waiting
  defp fixture_state(_fixture), do: :ready

  # The race is won the moment someone reaches it; until then, finishing a
  # match means someone conceded or retired, which is a different, rarer act.
  defp match_decided?(fixture) do
    at_race?(fixture, "a") or at_race?(fixture, "b")
  end

  defp frames_needed(fixture, side) do
    case {fixture.round.race_to, fixture_score(fixture, side)} do
      {race_to, nil} when is_integer(race_to) -> race_to
      {race_to, scored} when is_integer(race_to) -> max(race_to - scored, 0)
      _ -> nil
    end
  end

  defp at_race?(fixture, side), do: fixture_score(fixture, side) == fixture.round.race_to

  # --------------------------------------------- Circuit team event display

  # A blank or junk frame count is 0 rather than a crash: this is a correction
  # form, and the TD is often clearing a field before retyping it.
  defp to_frame_count(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {frames, _rest} when frames >= 0 -> frames
      _other -> 0
    end
  end

  defp to_frame_count(_value), do: 0

  @doc false
  def recorded_winner_id(%{result: %{winner_participation_id: id}}), do: id
  def recorded_winner_id(_fixture), do: nil

  @doc false
  def team_table_columns do
    [
      {"#", "Position", "text-left"},
      {"Team", "Team name", "text-left"},
      {"P", "Matches played", "text-right"},
      {"W", "Matches won", "text-right"},
      {"L", "Matches lost", "text-right"},
      {"FW", "Frames won", "text-right"},
      {"FD", "Frame difference", "text-right"},
      {"SP Points", "SportPesa Points", "text-right"}
    ]
  end

  @doc false
  def signed_number(value) when value > 0, do: "+#{value}"
  def signed_number(value), do: to_string(value)

  @doc false
  def team_rounds_in(rounds, sequence) do
    Enum.filter(rounds, &(&1.sequence == sequence))
  end

  @doc false
  def team_fixture_label(fixture) do
    case fixture_state(fixture) do
      :done -> "Final"
      :live -> "Live"
      :walkover -> "Walkover"
      _other -> "To play"
    end
  end

  @doc false
  def slot_time_label(fixture) do
    case Competitions.slot_start_in_eat(fixture) do
      nil -> nil
      start -> Calendar.strftime(start, "%H:%M")
    end
  end

  # A bracket result moves both players on to their next match; a round-robin
  # result moves the group table instead.
  defp result_recorded_note(%{category: "team"}),
    do: "Result recorded. The group table has moved."

  defp result_recorded_note(_assigns), do: "Result recorded. Both players have moved on."

  defp grassroots?(assigns), do: Stage.grassroots?(assigns.stage)

  defp circuit?(assigns), do: assigns.stage.name == "Circuit"

  defp regional?(assigns), do: assigns.stage.name == "Regional"

  # The formula-driven draw engine applies to: Grassroots Individual Male
  # with a venue selected (venue-scoped), or any Regional Individual/Team
  # category (region-scoped) — see the moduledoc.
  defp auto_draw_eligible?(assigns) do
    cond do
      circuit?(assigns) -> false
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

    cond do
      circuit?(socket.assigns) -> load_circuit(socket)
      auto_draw_eligible?(socket.assigns) -> load_gr(socket)
      true -> socket |> load_groups() |> load_unassigned()
    end
  end

  defp load_circuit(%{assigns: %{category: "team"}} = socket), do: load_circuit_teams(socket)

  defp load_circuit(socket) do
    %{stage: stage, category: category} = socket.assigns

    if connected?(socket), do: subscribe_to_circuit(stage.id, category)

    bracket = Competitions.load_bracket(stage.id, category)
    rounds = if bracket, do: bracket.rounds, else: []
    selected = keep_selected_fixture(socket, bracket)

    # Everything the chart needs is computed here rather than in the template.
    # A `<% x = ... %>` assignment in HEEx defeats change tracking for its
    # whole block, so LiveView re-sends it on every event — with a couple of
    # hundred match cards that is the entire bracket over the socket each time
    # a frame is tapped, which is what made the page feel broken.
    assign(socket,
      circuit_bracket: bracket,
      circuit_lanes: circuit_lane_data(rounds),
      circuit_numbers: circuit_match_numbers(rounds),
      circuit_counts: circuit_counts(rounds),
      circuit_first_knockout: first_knockout_sequence(rounds),
      circuit_selected_fixture:
        selected && circuit_fixture(%{circuit_bracket: bracket}, selected),
      circuit_editing: keep_editing?(socket, selected),
      # The entrant list is the pre-draw screen only — every use of it in the
      # template is inside `is_nil(@circuit_bracket)`. Loading it once a draw
      # exists fetched a few hundred players and their teams on every frame
      # tapped, to render none of them.
      circuit_entrants:
        if(bracket, do: [], else: Competitions.circuit_entrants(stage.id, category)),
      circuit_redraws_left: Competitions.circuit_redraws_remaining(stage.id, category),
      circuit_selected: selected,
      # Opens on one lane rather than all three. A 128 draw is 239 cards and
      # 127 connectors — around 400 KB of HTML, sent once over HTTP and again
      # when the socket connects — and laying that out is what made the page
      # slow to appear, not the queries behind it (those total ~40ms). The
      # full chart is still one click away in the view switcher.
      circuit_view: socket.assigns[:circuit_view] || :stage,
      circuit_side: socket.assigns[:circuit_side] || :winners,
      circuit_zoom: socket.assigns[:circuit_zoom] || :fit,
      circuit_filter: socket.assigns[:circuit_filter] || :all,
      circuit_notice: nil
    )
  end

  # The Circuit team event is round-robin, not a bracket: two national groups
  # of ten, one season-long round robin, top four in each to the Nationals
  # (spec 014). It reuses the same scoring handlers as the brackets — the
  # fixtures are ordinary fixtures — but its structure and table are its own.
  defp load_circuit_teams(socket) do
    %{stage: stage} = socket.assigns

    if connected?(socket), do: Competitions.subscribe_to_circuit_teams(stage.id)

    draw = Competitions.circuit_team_draw(stage.id)
    rounds = if draw, do: Competitions.circuit_team_rounds(stage.id), else: []
    selected = keep_selected_team_fixture(socket, rounds)

    assign(socket,
      circuit_team_draw: draw,
      circuit_team_rounds: rounds,
      circuit_team_standings:
        if(draw, do: Competitions.circuit_team_standings(stage.id), else: []),
      circuit_team_entrants: if(draw, do: [], else: Competitions.circuit_team_entrants(stage.id)),
      circuit_team_redraws_left: Competitions.circuit_team_redraws_remaining(stage.id),
      circuit_team_round: socket.assigns[:circuit_team_round] || 1,
      circuit_team_played?: Competitions.circuit_team_has_results?(stage.id),
      circuit_team_advancers:
        Competitions.get_or_create_group_config(stage.id, "team").advancer_count,
      circuit_team_view: socket.assigns[:circuit_team_view] || :table,
      circuit_selected: selected,
      circuit_selected_fixture: selected && team_fixture(rounds, selected),
      circuit_editing: keep_editing?(socket, selected),
      # The bracket assigns the shared template still reads.
      circuit_bracket: nil,
      circuit_lanes: [],
      circuit_numbers: %{},
      circuit_counts: %{},
      circuit_first_knockout: nil,
      circuit_entrants: [],
      circuit_redraws_left: 0,
      circuit_view: :chart,
      circuit_side: :winners,
      circuit_zoom: :fit,
      circuit_filter: :all,
      circuit_notice: nil
    )
  end

  # Same reason the bracket keeps its open card across a reload: every frame
  # tapped reloads, and a score panel that shut after each frame would send the
  # TD hunting for the match again mid-rack.
  defp keep_selected_team_fixture(socket, rounds) do
    case socket.assigns[:circuit_selected] do
      nil -> nil
      id -> if team_fixture(rounds, id), do: id
    end
  end

  # A correction in progress survives the reload that every frame triggers,
  # but not a change of match.
  defp keep_editing?(_socket, nil), do: false
  defp keep_editing?(socket, _selected), do: !!socket.assigns[:circuit_editing]

  defp team_fixture(rounds, id) do
    rounds
    |> Enum.flat_map(fn round -> Enum.map(round.fixtures, &%{&1 | round: round}) end)
    |> Enum.find(&(&1.id == id))
  end

  # Every frame tapped reloads the bracket, so the open match must survive that
  # reload — otherwise the score panel shuts after each frame and the TD has to
  # find the match again mid-rack. The selection is dropped only when the
  # fixture is no longer on screen, which is what happens on a category switch
  # or after a re-deal.
  defp keep_selected_fixture(socket, bracket) do
    selected = socket.assigns[:circuit_selected]

    cond do
      is_nil(selected) -> nil
      is_nil(bracket) -> nil
      fixture_in_bracket?(bracket, selected) -> selected
      true -> nil
    end
  end

  defp fixture_in_bracket?(%{rounds: rounds}, fixture_id) do
    Enum.any?(rounds, fn round -> Enum.any?(round.fixtures, &(&1.id == fixture_id)) end)
  end

  defp subscribe_to_circuit(stage_id, category) do
    case Competitions.get_knockout_bracket(stage_id, category) do
      nil -> :ok
      bracket -> Competitions.subscribe_to_bracket(bracket.id)
    end
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

  defp player_name(%{player: %{first_name: first, last_name: last}}),
    do: Names.full_name(first, last)

  defp player_name(_), do: "Team"

  ## View helpers

  # nil covers a bracket slot whose player is still to be decided.
  defp participant_name(nil), do: nil
  defp participant_name(%{player_id: nil, team: team}), do: Names.title_case(team.name)
  defp participant_name(%{player: %{first_name: f, last_name: l}}), do: Names.full_name(f, l)
  defp participant_name(%{team: %{name: name}}), do: name
  defp participant_name(_other), do: nil

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
