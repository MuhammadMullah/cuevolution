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

  alias Cuevolution.Competitions
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    unplayed = Competitions.list_unplayed_fixtures()
    played = Competitions.list_played_fixtures()

    {:ok,
     socket
     |> assign(
       page_title: "Results & Points",
       tab: "unplayed",
       selected_unplayed: nil,
       selected_played: nil,
       result_form: to_form(%{}, as: :result),
       correction_form: to_form(%{}, as: :result),
       points_forms: %{},
       unplayed_empty?: unplayed == [],
       played_empty?: played == []
     )
     |> stream(:unplayed, unplayed)
     |> stream(:played, played)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("select_fixture", %{"id" => id}, socket) do
    fixture = Enum.find(Competitions.list_unplayed_fixtures(), &(&1.id == id))

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
        played = Enum.find(Competitions.list_played_fixtures(), &(&1.id == fixture.id))

        {:noreply,
         socket
         |> stream_delete(:unplayed, fixture)
         |> stream_insert(:played, played, at: 0)
         |> assign(:selected_unplayed, nil)
         |> assign(:unplayed_empty?, Competitions.list_unplayed_fixtures() == [])
         |> assign(:played_empty?, false)
         |> put_flash(:info, "Result recorded.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :result_form, to_form(changeset, as: :result))}
    end
  end

  def handle_event("select_played", %{"id" => id}, socket) do
    fixture = Enum.find(Competitions.list_played_fixtures(), &(&1.id == id))

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

  defp fixture_label(fixture) do
    "#{Competitions.participant_name(fixture.participant_a)} vs #{Competitions.participant_name(fixture.participant_b)}"
  end
end
