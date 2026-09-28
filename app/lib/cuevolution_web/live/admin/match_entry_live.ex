defmodule CuevolutionWeb.Admin.MatchEntryLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Repo
  alias CuevolutionWeb.AdminComponents

  def status_label(%Fixture{status: "walkover", walkover_kind: "double"}),
    do: "NO RESULT — DEADLINE"

  def status_label(%Fixture{status: status}), do: status

  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Match entry",
       score_form: to_form(%{}, as: :result),
       correction_form: to_form(%{}, as: :result),
       selected_present: nil
     )
     |> load_fixture(id)}
  end

  def handle_event("record_final_score", %{"result" => params}, socket) do
    case Competitions.record_final_score(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           params
         ) do
      {:ok, _result} ->
        {:noreply, reload_fixture(socket, "Five frames recorded. Submit for verification.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to record results.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:score_form, to_form(params, as: :result))
         |> put_flash(:error, "Could not record score: #{format_error(reason)}")}
    end
  end

  def handle_event("verify", %{"result" => params}, socket) do
    case Competitions.verify_final_score(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           params
         ) do
      {:ok, _fixture} ->
        {:noreply, reload_fixture(socket, "Result verified and added to standings.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to verify results.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:correction_form, to_form(params, as: :result))
         |> put_flash(:error, "Could not verify result: #{format_error(reason)}")}
    end
  end

  def handle_event("postpone", %{"reason" => reason}, socket) do
    case Competitions.postpone_fixture(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           reason
         ) do
      {:ok, _fixture} ->
        {:noreply, reload_fixture(socket, "Fixture postponed.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to postpone fixtures.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not postpone fixture: #{format_error(reason)}")}
    end
  end

  def handle_event("resume", _params, socket) do
    case Competitions.resume_fixture(socket.assigns.fixture, socket.assigns.current_admin) do
      {:ok, _fixture} ->
        {:noreply, reload_fixture(socket, "Fixture resumed.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to resume fixtures.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not resume fixture: #{format_error(reason)}")}
    end
  end

  def handle_event("record_walkover", %{"participant_id" => participant_id}, socket) do
    case Competitions.record_walkover(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           participant_id
         ) do
      {:ok, _fixture} ->
        {:noreply, reload_fixture(socket, "Single walkover recorded.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to record walkovers.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not record walkover: #{format_error(reason)}")}
    end
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
            round: [group: :stage]
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
    |> put_flash(:info, message)
  end

  defp recorded_score_params(%Fixture{result: %{score: score}}) when is_map(score) do
    %{
      "participant_a_score" => Map.get(score, "participant_a_frames"),
      "participant_b_score" => Map.get(score, "participant_b_frames")
    }
  end

  defp recorded_score_params(_fixture), do: %{}

  defp format_error(:five_frames_required), do: "exactly five frame winners are required"
  defp format_error(:no_majority), do: "one participant must win at least three frames"
  defp format_error(:final_score_required), do: "enter both final scores"
  defp format_error(:invalid_final_score), do: "scores must be whole numbers from 0 to 5"
  defp format_error(:reason_required), do: "a reason is required"
  defp format_error(:invalid_fixture_state), do: "this fixture is not in an editable state"
  defp format_error(:participant_required), do: "choose the participant who was present"
  defp format_error(reason), do: inspect(reason)

  defp participant_label(participation), do: Competitions.participant_name(participation)
end
