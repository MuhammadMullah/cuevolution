defmodule CuevolutionWeb.AdminResultsLive do
  @moduledoc """
  Admin "Results & Points" page (spec 008).

  Two distinct audiences share this page, gated by permission (never by
  `role` directly — see `Admin.can?/2`):

    * A pure recorder (`record_results` but not `approve_results` — venue
      reps, regional coordinators) gets the Unplayed/Played tabs: record a
      fixture's winner (`Competitions.record_result/3`), then correct it
      (`correct_result/3`) while still awaiting approval.
    * An approver (`approve_results` — Tournament Director, Super Admin)
      gets the approval queue: bulk-approve many provisional results at
      once, or click into one to open the same detail panel a recorder
      uses — correct the winner, enter Cuevo Points, then approve just
      that fixture (`verify_result/2`). Either role also gets an
      "Approved" tab to revisit and correct already-final results —
      `can_correct_result?/2` lets an approver correct a result
      regardless of status, so this tab is just surfacing a capability
      the backend already grants both roles.

  Cuevo Points entry/correction (`record_points/3`/`correct_points/3`) only
  applies to Circuit/Finals-stage fixtures — Grassroots/Regional never
  award Cuevo Points (spec 008 FR-005).

  Team-category results are recorded at the team level (one winner, one
  optional score) — per-frame entry (`MatchFrame`) is supported by the
  context/data model but has no dedicated UI in this pass; frames can be
  entered by a follow-up admin tool once the league confirms its team-match
  frame format (spec 008 Edge Cases).
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    current_admin = socket.assigns.current_admin
    can_approve_results? = Admin.can?(current_admin, :approve_results)
    can_record_results? = Admin.can?(current_admin, :record_results)
    regions = if can_approve_results?, do: Accounts.list_regions(), else: []
    approval_venues = if can_approve_results?, do: Venues.list_venues(%{active: true}), else: []

    # Only loaded for a pure recorder (can_record_results? and not
    # can_approve_results?) — the only role combination whose Unplayed/Played
    # tabs actually render these (see the template). Super Admin and
    # Tournament Director also have can_record_results? == true, but neither
    # ever sees this tab (both hold `:approve_results` too, nationwide/
    # unscoped), so skipping the fetch for them avoids two unbounded,
    # deeply-preloaded, tournament-wide queries on every page load for data
    # that was being thrown away. They record a specific fixture's result
    # via `MatchEntryLive` instead (reached from Groups/Draws), which is
    # scoped to one fixture rather than listing every unplayed one.
    show_record_tabs? = can_record_results? and not can_approve_results?

    unplayed =
      if show_record_tabs?,
        do: Competitions.list_unplayed_fixtures_for_admin(current_admin),
        else: []

    played =
      if show_record_tabs?,
        do: Competitions.list_played_fixtures_for_admin(current_admin),
        else: []

    socket =
      socket
      |> assign(
        page_title: "Results & Points",
        tab: "unplayed",
        approval_tab: "pending",
        selected_unplayed: nil,
        selected_played: nil,
        result_form: to_form(%{}, as: :result),
        correction_form: to_form(%{}, as: :result),
        points_forms: %{},
        can_approve_results?: can_approve_results?,
        can_record_results?: can_record_results?,
        show_record_tabs?: show_record_tabs?,
        missing_scope?: missing_scope?(current_admin),
        approval_regions: regions,
        approval_venues: approval_venues,
        approval_region_id: nil,
        approval_venue_id: nil,
        approval_search: nil,
        approval_page: 1,
        approved_page: 1,
        selected_result_ids: MapSet.new(),
        unplayed_empty?: unplayed == [],
        played_empty?: played == []
      )
      |> assign_approval_search_form()
      |> load_pending_results()
      |> load_approved_results()
      |> stream(:unplayed, unplayed)
      |> stream(:played, played)

    {:ok, socket}
  end

  # A `record_results` holder whose own scope (venue for a venue rep, region
  # for a regional coordinator) hasn't been assigned yet sees `can_record_results?
  # == true` (role-based, scope-blind) but zero fixtures either way
  # (`scope_fixtures_for_admin` falls back to a never-matching clause without
  # one) — this tells them why, instead of a page that just looks broken.
  defp missing_scope?(%Admin{role: "venue_representative", venue_id: nil}), do: true
  defp missing_scope?(%Admin{role: "regional_coordinator", region_id: nil}), do: true
  defp missing_scope?(%Admin{}), do: false

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("filter_approval", %{"region_id" => region_id, "venue_id" => venue_id}, socket) do
    region_id = blank_to_nil(region_id)
    venues = approval_venues_for_region(region_id)
    venue_id = valid_venue_id(venues, venue_id)

    {:noreply,
     socket
     |> assign(:approval_venues, venues)
     |> assign(:approval_region_id, region_id)
     |> assign(:approval_venue_id, venue_id)
     |> assign(:approval_page, 1)
     |> assign(:approved_page, 1)
     |> assign(:selected_result_ids, MapSet.new())
     |> load_pending_results()
     |> load_approved_results()}
  end

  def handle_event("clear_approval_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:approval_venues, approval_venues_for_region(nil))
     |> assign(:approval_region_id, nil)
     |> assign(:approval_venue_id, nil)
     |> assign(:approval_page, 1)
     |> assign(:approved_page, 1)
     |> assign(:selected_result_ids, MapSet.new())
     |> load_pending_results()
     |> load_approved_results()}
  end

  def handle_event("search_approval", %{"search" => %{"term" => term}}, socket) do
    {:noreply,
     socket
     |> assign(:approval_search, blank_to_nil(term))
     |> assign(:approval_page, 1)
     |> assign(:approved_page, 1)
     |> assign_approval_search_form()
     |> load_pending_results()
     |> load_approved_results()}
  end

  def handle_event("clear_approval_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:approval_search, nil)
     |> assign(:approval_page, 1)
     |> assign(:approved_page, 1)
     |> assign_approval_search_form()
     |> load_pending_results()
     |> load_approved_results()}
  end

  def handle_event("change_approval_page", %{"page" => page}, socket) do
    page = parse_page(page, socket.assigns.approval_total_pages)

    {:noreply,
     socket
     |> assign(:approval_page, page)
     |> assign(:selected_result_ids, MapSet.new())
     |> load_pending_results()}
  end

  def handle_event("change_approved_page", %{"page" => page}, socket) do
    page = parse_page(page, socket.assigns.approved_total_pages)

    {:noreply,
     socket
     |> assign(:approved_page, page)
     |> load_approved_results()}
  end

  # Super Admin-only toggle inside the approval section: "pending" (the
  # existing checkbox approval queue) vs "approved" (browse already-final
  # results to edit — see `can_correct_result?/2`). Switching tabs clears
  # any selected fixture so a stale correction form from the other tab
  # doesn't linger.
  def handle_event("switch_approval_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:approval_tab, tab)
     |> assign(:selected_played, nil)
     |> assign(:correction_form, to_form(%{}, as: :result))
     |> assign(:points_forms, %{})}
  end

  def handle_event("toggle_result_selection", %{"id" => id}, socket) do
    selected_result_ids = socket.assigns.selected_result_ids

    selected_result_ids =
      if MapSet.member?(selected_result_ids, id),
        do: MapSet.delete(selected_result_ids, id),
        else: MapSet.put(selected_result_ids, id)

    {:noreply, assign(socket, :selected_result_ids, selected_result_ids)}
  end

  def handle_event("approve_selected_results", _params, socket) do
    fixture_ids = MapSet.to_list(socket.assigns.selected_result_ids)

    case Competitions.approve_pending_results(socket.assigns.current_admin, fixture_ids) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:selected_result_ids, MapSet.new())
         |> load_pending_results()
         |> put_flash(:info, "#{count} result#{if count == 1, do: "", else: "s"} approved.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve results.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The selected results could not be approved.")}
    end
  end

  def handle_event("select_fixture", %{"id" => id}, socket) do
    fixture = Competitions.get_unplayed_fixture_for_admin(socket.assigns.current_admin, id)

    {:noreply,
     socket
     |> assign(:selected_unplayed, fixture)
     |> assign(:result_form, to_form(%{}, as: :result))}
  end

  def handle_event("record_result", %{"result" => params}, socket) do
    fixture = socket.assigns.selected_unplayed

    case resolve_winner(params, fixture.participant_a_id, fixture.participant_b_id) do
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:ok, winner_id} ->
        attrs = %{"winner_participation_id" => winner_id, "score" => result_score(params)}

        case Competitions.record_result(fixture, socket.assigns.current_admin, attrs) do
          {:ok, _result} ->
            played =
              Competitions.get_played_fixture_for_admin(socket.assigns.current_admin, fixture.id)

            {:noreply,
             socket
             |> stream_delete(:unplayed, fixture)
             |> stream_insert(:played, played, at: 0)
             |> assign(:selected_unplayed, nil)
             |> assign(
               :unplayed_empty?,
               Competitions.list_unplayed_fixtures_for_admin(socket.assigns.current_admin) == []
             )
             |> assign(:played_empty?, false)
             |> put_flash(:info, "Result recorded.")}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "You don't have permission to record results.")}

          {:error, changeset} ->
            {:noreply, assign(socket, :result_form, to_form(changeset, as: :result))}
        end
    end
  end

  # Opens the shared detail modal — reached from the recorder's Played tab,
  # the approver's pending-approval queue (correct/enter points before
  # approving a single fixture), or Super Admin's Approved tab.
  def handle_event("select_played", %{"id" => id}, socket) do
    fixture = Competitions.get_played_fixture_for_admin(socket.assigns.current_admin, id)

    {:noreply,
     socket
     |> assign(:selected_played, fixture)
     |> assign(:correction_form, correction_form_for(fixture))
     |> assign(:points_forms, build_points_forms(fixture))}
  end

  def handle_event("close_result_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_played, nil)
     |> assign(:correction_form, to_form(%{}, as: :result))
     |> assign(:points_forms, %{})}
  end

  def handle_event("approve_result", _params, socket) do
    fixture = socket.assigns.selected_played

    case Competitions.verify_result(fixture, socket.assigns.current_admin) do
      {:ok, _verified} ->
        updated =
          Competitions.get_played_fixture_for_admin(socket.assigns.current_admin, fixture.id)

        {:noreply,
         socket
         |> assign(:selected_played, updated)
         |> assign(
           :selected_result_ids,
           MapSet.delete(socket.assigns.selected_result_ids, fixture.id)
         )
         |> load_pending_results()
         |> refresh_approved_stream(updated)
         |> put_flash(:info, "Result approved and finalized.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve results.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This result could not be approved.")}
    end
  end

  def handle_event("correct_result", %{"result" => params}, socket) do
    fixture = socket.assigns.selected_played

    case resolve_winner(params, fixture.participant_a_id, fixture.participant_b_id) do
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:ok, winner_id} ->
        attrs = %{"winner_participation_id" => winner_id, "score" => result_score(params)}

        case Competitions.correct_result(fixture.result, socket.assigns.current_admin, attrs) do
          {:ok, _corrected} ->
            updated =
              Competitions.get_played_fixture_for_admin(socket.assigns.current_admin, fixture.id)

            {:noreply,
             socket
             |> stream_insert(:played, updated, at: -1)
             |> refresh_approved_stream(updated)
             |> assign(:selected_played, nil)
             |> assign(:correction_form, to_form(%{}, as: :result))
             |> assign(:points_forms, %{})
             |> put_flash(
               :info,
               "Result corrected. Review this fixture's downstream advancement."
             )}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "You don't have permission to correct results.")}

          {:error, :already_approved} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "This result has already been approved — ask a tournament director to correct it."
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, :correction_form, to_form(changeset, as: :result))}
        end
    end
  end

  def handle_event(
        "record_points",
        %{"participant_id" => participant_id, "points" => points},
        socket
      ) do
    fixture = socket.assigns.selected_played
    attrs = %{"participant_id" => participant_id, "points" => points}

    case Competitions.record_points(fixture.result, socket.assigns.current_admin, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> assign(:points_forms, build_points_forms(fixture))
         |> put_flash(:info, "Points recorded.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to record points.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't record points — check the value.")}
    end
  end

  def handle_event("correct_points", %{"entry_id" => entry_id, "points" => points}, socket) do
    fixture = socket.assigns.selected_played

    entry =
      Enum.find(Competitions.points_entries_for_result(fixture.result_id), &(&1.id == entry_id))

    case Competitions.correct_points(entry, socket.assigns.current_admin, %{"points" => points}) do
      {:ok, _corrected} ->
        {:noreply,
         socket
         |> assign(:points_forms, build_points_forms(fixture))
         |> put_flash(:info, "Points corrected.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to correct points.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't correct points — check the value.")}
    end
  end

  # Frame scores, when given, are the source of truth for who won — this
  # keeps the winner from going stale after someone edits just the score
  # without also re-picking the radio (the submitted
  # `winner_participation_id` is only used as a fallback when no score was
  # entered, e.g. a walkover).
  defp resolve_winner(params, participant_a_id, participant_b_id) do
    case derive_winner_from_score(params, participant_a_id, participant_b_id) do
      {:ok, winner_id} ->
        {:ok, winner_id}

      :tied ->
        {:error, "Frame scores can't be tied — enter a score with a clear winner."}

      :no_score ->
        case params["winner_participation_id"] do
          id when id in [nil, ""] -> {:error, "Pick a winner or enter the frame score."}
          id -> {:ok, id}
        end
    end
  end

  defp derive_winner_from_score(
         %{"participant_a_frames" => a, "participant_b_frames" => b},
         participant_a_id,
         participant_b_id
       )
       when a not in [nil, ""] and b not in [nil, ""] do
    with {a_frames, ""} <- Integer.parse(a),
         {b_frames, ""} <- Integer.parse(b) do
      cond do
        a_frames > b_frames -> {:ok, participant_a_id}
        b_frames > a_frames -> {:ok, participant_b_id}
        true -> :tied
      end
    else
      _ -> :no_score
    end
  end

  defp derive_winner_from_score(_params, _a_id, _b_id), do: :no_score

  defp result_score(%{"participant_a_frames" => a, "participant_b_frames" => b})
       when a not in [nil, ""] and b not in [nil, ""] do
    %{
      "participant_a_frames" => String.to_integer(a),
      "participant_b_frames" => String.to_integer(b)
    }
  end

  defp result_score(_params), do: nil

  # Prefills the correction form with the currently recorded winner and
  # frame score, so editing a result starts from what's already saved
  # instead of a blank form.
  defp correction_form_for(fixture) do
    score = fixture.result.score || %{}

    to_form(
      %{
        "winner_participation_id" => fixture.result.winner_participation_id,
        "participant_a_frames" => Map.get(score, "participant_a_frames"),
        "participant_b_frames" => Map.get(score, "participant_b_frames")
      },
      as: :result
    )
  end

  defp build_points_forms(fixture) do
    entries = Competitions.points_entries_for_result(fixture.result_id)

    [fixture.participant_a, fixture.participant_b]
    |> Enum.map(fn participant ->
      entry = Enum.find(entries, &(&1.participant_id == participant.id))

      {participant.id,
       %{participant: participant, entry: entry, total: Competitions.points_total(participant.id)}}
    end)
    |> Map.new()
  end

  defp points_eligible?(%{participant_a: %{stage: %{order: order}}}), do: order >= 3

  # Mirrors `Competitions.correct_result/3`'s authorization: an approver can
  # always correct; a recorder (e.g. a venue rep) only while the result is
  # still awaiting approval. Keeps the UI from offering a form the backend
  # would reject anyway.
  defp can_correct_result?(admin, fixture) do
    Admin.can?(admin, :approve_results) or
      (Admin.can?(admin, :record_results) and fixture.status == "completed")
  end

  defp fixture_label(fixture) do
    "#{Competitions.participant_name(fixture.participant_a)} vs #{Competitions.participant_name(fixture.participant_b)}"
  end

  defp approval_venues_for_region(nil), do: Venues.list_venues(%{active: true})
  defp approval_venues_for_region(region_id), do: Venues.list_active_for_region(region_id)

  defp valid_venue_id(_venues, value) when value in [nil, ""], do: nil

  defp valid_venue_id(venues, value) do
    if Enum.any?(venues, &(&1.id == value)), do: value, else: nil
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp assign_approval_search_form(socket) do
    assign(
      socket,
      :approval_search_form,
      to_form(%{"term" => socket.assigns.approval_search}, as: :search)
    )
  end

  defp load_pending_results(socket) do
    if socket.assigns.can_approve_results? do
      %{
        approval_region_id: region_id,
        approval_venue_id: venue_id,
        approval_search: search,
        approval_page: page
      } = socket.assigns

      per_page = Competitions.pending_results_per_page()
      total_count = Competitions.count_pending_result_fixtures(region_id, venue_id, search)
      total_pages = max(1, ceil(total_count / per_page))
      page = page |> max(1) |> min(total_pages)

      pending_results =
        Competitions.list_pending_result_fixtures(region_id, venue_id, page, search)

      socket
      |> assign(:approval_page, page)
      |> assign(:approval_total_pages, total_pages)
      |> assign(:pending_results_empty?, pending_results == [])
      |> stream(:pending_results, pending_results, reset: true)
    else
      socket
      |> assign(:approval_page, 1)
      |> assign(:approval_total_pages, 1)
      |> assign(:pending_results_empty?, true)
      |> stream(:pending_results, [], reset: true)
    end
  end

  defp refresh_approved_stream(socket, %{status: "verified"} = fixture),
    do: stream_insert(socket, :approved_results, fixture, at: -1)

  defp refresh_approved_stream(socket, %{}), do: socket

  defp load_approved_results(socket) do
    if socket.assigns.can_approve_results? do
      %{
        approval_region_id: region_id,
        approval_venue_id: venue_id,
        approval_search: search,
        approved_page: page
      } = socket.assigns

      per_page = Competitions.pending_results_per_page()
      total_count = Competitions.count_approved_result_fixtures(region_id, venue_id, search)
      total_pages = max(1, ceil(total_count / per_page))
      page = page |> max(1) |> min(total_pages)

      approved_results =
        Competitions.list_approved_result_fixtures(region_id, venue_id, page, search)

      socket
      |> assign(:approved_page, page)
      |> assign(:approved_total_pages, total_pages)
      |> assign(:approved_results_empty?, approved_results == [])
      |> stream(:approved_results, approved_results, reset: true)
    else
      socket
      |> assign(:approved_page, 1)
      |> assign(:approved_total_pages, 1)
      |> assign(:approved_results_empty?, true)
      |> stream(:approved_results, [], reset: true)
    end
  end

  defp parse_page(page, total_pages) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} -> parse_page(page, total_pages)
      _ -> 1
    end
  end

  defp parse_page(page, total_pages) when is_integer(page),
    do: page |> max(1) |> min(max(total_pages, 1))

  defp parse_page(_page, _total_pages), do: 1

  defp fixture_venue_label(%{venue: %{name: name}}), do: name

  defp fixture_venue_label(%{match_id: match_id}) when is_binary(match_id),
    do: "Grassroots · self-organised"

  defp fixture_venue_label(_fixture), do: "Venue not assigned"

  defp played_fixture_summary(%{walkover_kind: "double"}), do: "NO RESULT — DEADLINE"

  defp played_fixture_summary(%{status: "completed"} = fixture) do
    "Pending approval · #{winner_label(fixture)}"
  end

  defp played_fixture_summary(%{status: "verified"} = fixture) do
    "Final · #{winner_label(fixture)}"
  end

  defp played_fixture_summary(fixture) do
    winner_label(fixture)
  end

  defp winner_label(fixture) do
    "Winner: #{Competitions.participant_name(fixture.result.winner_participation)}"
  end

  # Shared between the Played tab (record_results holders), the approval
  # queue's pending results, and the Super Admin-only Approved tab — same
  # approve/correct/points affordances, gated the same way by
  # `can_correct_result?/2` and `Admin.can?/2`, just reached from a
  # different list. Renders as a modal so the underlying list keeps its
  # full width instead of permanently reserving a side column for it.
  attr :current_admin, :map, required: true
  attr :selected_played, :map, required: true
  attr :correction_form, :map, required: true
  attr :points_forms, :map, required: true

  defp result_detail_panel(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink-950/50 px-4 py-4 sm:items-center sm:py-8"
      phx-click-away="close_result_detail"
    >
      <div class="max-h-[calc(100dvh-2rem)] w-full max-w-[560px] overflow-y-auto rounded-2xl bg-white shadow-xl sm:max-h-[calc(100dvh-4rem)]">
        <div class="relative border-b border-ink-100 px-5 py-4.5 sm:px-6">
          <button
            type="button"
            phx-click="close_result_detail"
            class="absolute right-4 top-4 flex size-[30px] items-center justify-center rounded-full text-ink-400 hover:bg-ink-100 hover:text-ink-950"
          >
            ✕
          </button>
          <h2 class="pr-8 text-[16px] font-bold tracking-tight text-ink-950">
            {Competitions.participant_name(@selected_played.participant_a)} vs {Competitions.participant_name(
              @selected_played.participant_b
            )}
          </h2>
          <p class="mt-0.5 text-[12.5px] text-ink-500">{fixture_venue_label(@selected_played)}</p>
        </div>

        <div class="flex flex-col gap-4 p-4.5 sm:p-5">
          <div>
            <div
              :if={@selected_played.status == "completed"}
              class="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-[12.5px] text-amber-800"
            >
              Awaiting tournament director approval. This result is not final yet.
            </div>
            <div
              :if={@selected_played.status == "verified"}
              class="mb-3 rounded-lg bg-emerald-50 px-3 py-2 text-[12.5px] text-emerald-800"
            >
              Approved and final.
            </div>
            <button
              :if={
                @selected_played.status == "completed" &&
                  Admin.can?(@current_admin, :approve_results)
              }
              id="approve-result"
              type="button"
              phx-click="approve_result"
              class="mb-3 w-full rounded-full bg-ink-950 px-4 py-2 text-[13px] font-semibold text-white hover:bg-ink-800"
            >
              Approve and finalize result
            </button>
            <h3
              :if={can_correct_result?(@current_admin, @selected_played)}
              class="mb-2 text-[14.5px] font-bold text-ink-950"
            >
              Correct result
            </h3>
            <div
              :if={can_correct_result?(@current_admin, @selected_played)}
              class="mb-2.5 rounded-lg bg-amber-50 px-3 py-2 text-[12.5px] text-amber-800"
            >
              Correcting this result may affect standings and any stage advancement already made from it — review before saving.
            </div>
            <.form
              :if={can_correct_result?(@current_admin, @selected_played)}
              for={@correction_form}
              phx-submit="correct_result"
              class="flex flex-col gap-2.5"
            >
              <label class="flex items-center gap-2 text-[13.5px] text-ink-700">
                <input
                  type="radio"
                  name="result[winner_participation_id]"
                  value={@selected_played.participant_a_id}
                  checked={
                    @correction_form[:winner_participation_id].value ==
                      @selected_played.participant_a_id
                  }
                />
                {Competitions.participant_name(@selected_played.participant_a)} wins
              </label>
              <label class="flex items-center gap-2 text-[13.5px] text-ink-700">
                <input
                  type="radio"
                  name="result[winner_participation_id]"
                  value={@selected_played.participant_b_id}
                  checked={
                    @correction_form[:winner_participation_id].value ==
                      @selected_played.participant_b_id
                  }
                />
                {Competitions.participant_name(@selected_played.participant_b)} wins
              </label>
              <div class="flex items-center gap-2">
                <input
                  type="number"
                  name="result[participant_a_frames]"
                  value={@correction_form[:participant_a_frames].value}
                  placeholder="A frames (optional)"
                  class="w-1/2 rounded-lg border border-ink-300 bg-white px-2.5 py-2 text-[13px] text-ink-950 placeholder:text-ink-400"
                />
                <input
                  type="number"
                  name="result[participant_b_frames]"
                  value={@correction_form[:participant_b_frames].value}
                  placeholder="B frames (optional)"
                  class="w-1/2 rounded-lg border border-ink-300 bg-white px-2.5 py-2 text-[13px] text-ink-950 placeholder:text-ink-400"
                />
              </div>
              <button
                type="submit"
                class="rounded-full border border-ink-300 px-4 py-2 text-[13px] font-semibold text-ink-700 hover:bg-ink-50"
              >
                Save correction
              </button>
            </.form>
          </div>

          <div :if={points_eligible?(@selected_played)} class="border-t border-ink-100 pt-3.5">
            <h3 class="mb-2 text-[14.5px] font-bold text-ink-950">Cuevo Points</h3>
            <div
              :for={{_id, %{participant: participant, entry: entry, total: total}} <- @points_forms}
              class="mb-3"
            >
              <div class="mb-1 flex items-center justify-between text-[13.5px] font-semibold text-ink-950">
                <span>{Competitions.participant_name(participant)}</span>
                <span class="font-mono text-[12.5px] text-ink-500">total: {total}</span>
              </div>
              <form
                :if={is_nil(entry)}
                id={"record-points-#{participant.id}"}
                phx-submit="record_points"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="participant_id" value={participant.id} />
                <input
                  type="number"
                  name="points"
                  placeholder="Points"
                  class="w-24 rounded-lg border border-ink-300 px-2.5 py-2 text-[13px]"
                />
                <button
                  type="submit"
                  class="rounded-full bg-ink-950 px-3.5 py-[7px] text-[13px] font-semibold text-white hover:bg-ink-900"
                >
                  Add
                </button>
              </form>
              <form
                :if={entry}
                id={"correct-points-#{participant.id}"}
                phx-submit="correct_points"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="entry_id" value={entry.id} />
                <input
                  type="number"
                  name="points"
                  value={entry.points}
                  class="w-24 rounded-lg border border-ink-300 px-2.5 py-2 text-[13px]"
                />
                <button
                  type="submit"
                  class="rounded-full border border-ink-300 px-3.5 py-[7px] text-[13px] font-semibold text-ink-700 hover:bg-ink-50"
                >
                  Correct
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
