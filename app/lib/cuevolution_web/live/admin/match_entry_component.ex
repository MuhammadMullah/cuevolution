defmodule CuevolutionWeb.Admin.MatchEntryComponent do
  @moduledoc """
  Match entry/verification, as a `LiveComponent` — the same record/verify/
  postpone/walkover flow `MatchEntryLive` exposes as a standalone page, but
  embeddable in a slide-over panel (see `GroupManagementLive`'s group
  fixture list) so an admin never has to leave the page they're scoring
  from. A LiveComponent runs in its parent LiveView's own process, so every
  state-changing action here `send/2`s `{:match_entry_updated, fixture_id}`
  straight to that process — the parent's `handle_info/2` decides how to
  refresh around the panel (e.g. `GroupManagementLive` re-runs `load_gr/1`
  to pick up the fixture's new status in its group cards).
  """
  use CuevolutionWeb, :live_component

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Repo

  def status_label(%Fixture{status: "walkover", walkover_kind: "double"}),
    do: "NO RESULT — DEADLINE"

  def status_label(%Fixture{status: status}), do: status

  def regional_fixture?(%Fixture{round: %{stage: %{name: "Regional"}}}), do: true
  def regional_fixture?(%Fixture{}), do: false

  def max_frame_score(fixture), do: if(regional_fixture?(fixture), do: "4", else: "5")

  # Plain `put_flash/3` doesn't surface anywhere for a LiveComponent — it
  # sets flash on this component's own isolated socket, which nothing ever
  # renders (the page's flash group reads the *LiveView's* `@flash`). So
  # messages here live in a local `@banner` assign instead, rendered inline
  # in the panel next to whichever form produced them.
  def update(%{fixture_id: fixture_id} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       score_form: to_form(%{}, as: :result),
       correction_form: to_form(%{}, as: :result),
       banner: nil
     )
     |> load_fixture(fixture_id)}
  end

  def handle_event("record_final_score", %{"result" => params}, socket) do
    case Competitions.record_final_score(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           params
         ) do
      {:ok, _result} ->
        frame_count = if regional_fixture?(socket.assigns.fixture), do: "Four", else: "Five"

        {:noreply,
         socket
         |> notify_parent()
         |> reload_fixture("#{frame_count} frames recorded. Submit for verification.")}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :banner, {:error, "You don't have permission to record results."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:score_form, to_form(params, as: :result))
         |> assign(
           :banner,
           {:error, "Could not record score: #{format_error(reason, socket.assigns.fixture)}"}
         )}
    end
  end

  def handle_event("verify", %{"result" => params}, socket) do
    case Competitions.verify_final_score(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           params
         ) do
      {:ok, _fixture} ->
        {:noreply,
         socket
         |> notify_parent()
         |> reload_fixture("Result verified and added to standings.")}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :banner, {:error, "You don't have permission to verify results."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:correction_form, to_form(params, as: :result))
         |> assign(
           :banner,
           {:error, "Could not verify result: #{format_error(reason, socket.assigns.fixture)}"}
         )}
    end
  end

  def handle_event("postpone", %{"reason" => reason}, socket) do
    case Competitions.postpone_fixture(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           reason
         ) do
      {:ok, _fixture} ->
        {:noreply, socket |> notify_parent() |> reload_fixture("Fixture postponed.")}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :banner, {:error, "You don't have permission to postpone fixtures."})}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :banner,
           {:error, "Could not postpone fixture: #{format_error(reason, socket.assigns.fixture)}"}
         )}
    end
  end

  def handle_event("resume", _params, socket) do
    case Competitions.resume_fixture(socket.assigns.fixture, socket.assigns.current_admin) do
      {:ok, _fixture} ->
        {:noreply, socket |> notify_parent() |> reload_fixture("Fixture resumed.")}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :banner, {:error, "You don't have permission to resume fixtures."})}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :banner,
           {:error, "Could not resume fixture: #{format_error(reason, socket.assigns.fixture)}"}
         )}
    end
  end

  def handle_event("record_walkover", %{"participant_id" => participant_id}, socket) do
    case Competitions.record_walkover(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           participant_id
         ) do
      {:ok, _fixture} ->
        {:noreply, socket |> notify_parent() |> reload_fixture("Single walkover recorded.")}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, :banner, {:error, "You don't have permission to record walkovers."})}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :banner,
           {:error, "Could not record walkover: #{format_error(reason, socket.assigns.fixture)}"}
         )}
    end
  end

  defp notify_parent(socket) do
    send(self(), {:match_entry_updated, socket.assigns.fixture.id})
    socket
  end

  defp load_fixture(socket, id) do
    fixture =
      Fixture
      |> Repo.get(id)
      |> case do
        nil ->
          nil

        fixture ->
          Repo.preload(fixture,
            result: :match_frames,
            participant_a: :player,
            participant_b: :player,
            round: :stage
          )
      end

    assign(socket,
      fixture: fixture,
      correction_form: to_form(recorded_score_params(fixture), as: :result)
    )
  end

  defp reload_fixture(socket, message) do
    socket
    |> load_fixture(socket.assigns.fixture.id)
    |> assign(:score_form, to_form(%{}, as: :result))
    |> assign(:banner, {:info, message})
  end

  defp recorded_score_params(%Fixture{result: %{score: score}}) when is_map(score) do
    %{
      "participant_a_score" => Map.get(score, "participant_a_frames"),
      "participant_b_score" => Map.get(score, "participant_b_frames")
    }
  end

  defp recorded_score_params(_fixture), do: %{}

  defp format_error(:five_frames_required, _fixture),
    do: "exactly five frame winners are required"

  defp format_error(:no_majority, _fixture), do: "one participant must win at least three frames"
  defp format_error(:final_score_required, _fixture), do: "enter both final scores"

  defp format_error(:invalid_final_score, fixture) do
    if regional_fixture?(fixture),
      do: "scores must be whole numbers from 0 to 4, summing to 4",
      else: "scores must be whole numbers from 0 to 5"
  end

  defp format_error(:reason_required, _fixture), do: "a reason is required"

  defp format_error(:invalid_fixture_state, _fixture),
    do: "this fixture is not in an editable state"

  defp format_error(:results_recording_closed, _fixture), do: "results recording has closed"

  defp format_error(:participant_required, _fixture),
    do: "choose the participant who was present"

  defp format_error(reason, _fixture), do: inspect(reason)

  defp participant_label(participation), do: Competitions.participant_name(participation)
end
