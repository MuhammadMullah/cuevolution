defmodule CuevolutionWeb.AdminResultsLive do
  @moduledoc """
  Admin "Results & Points" page (spec 008) — Unplayed tab records a
  fixture's winner (`Competitions.record_result/3`); Played tab shows the
  recorded winner with a correction affordance (`correct_result/3`) and, for
  Circuit/Finals-stage fixtures only, Cuevo Points entry/correction per
  participant (`record_points/3`/`correct_points/3` — Grassroots/Regional
  never award Cuevo Points, spec 008 FR-005).

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

    unplayed =
      if can_record_results?,
        do: Competitions.list_unplayed_fixtures_for_admin(current_admin),
        else: []

    played =
      if can_record_results?,
        do: Competitions.list_played_fixtures_for_admin(current_admin),
        else: []

    socket =
      socket
      |> assign(
        page_title: "Results & Points",
        tab: "unplayed",
        selected_unplayed: nil,
        selected_played: nil,
        result_form: to_form(%{}, as: :result),
        correction_form: to_form(%{}, as: :result),
        points_forms: %{},
        can_approve_results?: can_approve_results?,
        can_record_results?: can_record_results?,
        missing_scope?: missing_scope?(current_admin),
        approval_regions: regions,
        approval_venues: approval_venues,
        approval_region_id: nil,
        approval_venue_id: nil,
        approval_page: 1,
        selected_result_ids: MapSet.new(),
        unplayed_empty?: unplayed == [],
        played_empty?: played == []
      )
      |> load_pending_results()
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
     |> assign(:selected_result_ids, MapSet.new())
     |> load_pending_results()}
  end

  def handle_event("change_approval_page", %{"page" => page}, socket) do
    page = parse_page(page, socket.assigns.approval_total_pages)

    {:noreply,
     socket
     |> assign(:approval_page, page)
     |> assign(:selected_result_ids, MapSet.new())
     |> load_pending_results()}
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
    fixture =
      socket.assigns.current_admin
      |> Competitions.list_unplayed_fixtures_for_admin()
      |> Enum.find(&(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_unplayed, fixture)
     |> assign(:result_form, to_form(%{}, as: :result))}
  end

  def handle_event("record_result", %{"result" => params}, socket) do
    fixture = socket.assigns.selected_unplayed

    attrs = %{
      "winner_participation_id" => params["winner_participation_id"],
      "score" => result_score(params)
    }

    case Competitions.record_result(fixture, socket.assigns.current_admin, attrs) do
      {:ok, _result} ->
        played =
          socket.assigns.current_admin
          |> Competitions.list_played_fixtures_for_admin()
          |> Enum.find(&(&1.id == fixture.id))

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

  def handle_event("select_played", %{"id" => id}, socket) do
    fixture =
      socket.assigns.current_admin
      |> Competitions.list_played_fixtures_for_admin()
      |> Enum.find(&(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_played, fixture)
     |> assign(
       :correction_form,
       to_form(%{"winner_participation_id" => fixture.result.winner_participation_id},
         as: :result
       )
     )
     |> assign(:points_forms, build_points_forms(fixture))}
  end

  def handle_event("approve_result", _params, socket) do
    fixture = socket.assigns.selected_played

    case Competitions.verify_result(fixture, socket.assigns.current_admin) do
      {:ok, _verified} ->
        updated =
          socket.assigns.current_admin
          |> Competitions.list_played_fixtures_for_admin()
          |> Enum.find(&(&1.id == fixture.id))

        {:noreply,
         socket
         |> stream_insert(:played, updated, at: 0)
         |> assign(:selected_played, updated)
         |> put_flash(:info, "Result approved and finalized.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve results.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This result could not be approved.")}
    end
  end

  def handle_event("correct_result", %{"result" => params}, socket) do
    fixture = socket.assigns.selected_played

    attrs = %{
      "winner_participation_id" => params["winner_participation_id"],
      "score" => result_score(params)
    }

    case Competitions.correct_result(fixture.result, socket.assigns.current_admin, attrs) do
      {:ok, _corrected} ->
        updated = Enum.find(Competitions.list_played_fixtures(), &(&1.id == fixture.id))

        {:noreply,
         socket
         |> stream_insert(:played, updated, at: -1)
         |> assign(:selected_played, updated)
         |> assign(:points_forms, build_points_forms(updated))
         |> put_flash(:info, "Result corrected. Review this fixture's downstream advancement.")}

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

  defp result_score(%{"participant_a_frames" => a, "participant_b_frames" => b})
       when a not in [nil, ""] and b not in [nil, ""] do
    %{
      "participant_a_frames" => String.to_integer(a),
      "participant_b_frames" => String.to_integer(b)
    }
  end

  defp result_score(_params), do: nil

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

  defp load_pending_results(socket) do
    if socket.assigns.can_approve_results? do
      %{approval_region_id: region_id, approval_venue_id: venue_id, approval_page: page} =
        socket.assigns

      per_page = Competitions.pending_results_per_page()
      total_count = Competitions.count_pending_result_fixtures(region_id, venue_id)
      total_pages = max(1, ceil(total_count / per_page))
      page = page |> max(1) |> min(total_pages)
      pending_results = Competitions.list_pending_result_fixtures(region_id, venue_id, page)

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
end
