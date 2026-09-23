defmodule CuevolutionWeb.Admin.MatchEntryLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Repo
  alias CuevolutionWeb.AdminComponents

  def mount(%{"id" => id}, _session, socket) do
    fixture =
      Fixture
      |> Repo.get(id)
      |> case do
        nil ->
          nil

        fixture ->
          Repo.preload(fixture, [
            :result,
            participant_a: :player,
            participant_b: :player,
            round: [group: :stage]
          ])
      end

    {:ok,
     socket
     |> assign(
       page_title: "Match entry",
       fixture: fixture,
       frame_winners: %{},
       correction_winners: %{},
       selected_present: nil
     )}
  end

  def handle_event("set_frame", %{"sequence" => sequence, "winner" => winner}, socket) do
    {:noreply, update(socket, :frame_winners, &Map.put(&1, sequence, winner))}
  end

  def handle_event("record_frames", _params, socket) do
    winners = Enum.map(1..5, &Map.get(socket.assigns.frame_winners, to_string(&1)))

    case Competitions.record_frames(socket.assigns.fixture, socket.assigns.current_admin, winners) do
      {:ok, _result} ->
        {:noreply, reload_fixture(socket, "Five frames recorded. Submit for verification.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to record results.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not record frames: #{format_error(reason)}")}
    end
  end

  def handle_event("verify", _params, socket) do
    case Competitions.verify_result(socket.assigns.fixture, socket.assigns.current_admin) do
      {:ok, _fixture} ->
        {:noreply, reload_fixture(socket, "Result verified and added to standings.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to verify results.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not verify result: #{format_error(reason)}")}
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

  defp reload_fixture(socket, message) do
    fixture =
      socket.assigns.fixture.id
      |> then(&Repo.get!(Fixture, &1))
      |> Repo.preload([
        :result,
        participant_a: :player,
        participant_b: :player,
        round: [group: :stage]
      ])

    socket |> assign(:fixture, fixture) |> put_flash(:info, message)
  end

  defp format_error(:five_frames_required), do: "exactly five frame winners are required"
  defp format_error(:no_majority), do: "one participant must win at least three frames"
  defp format_error(:reason_required), do: "a reason is required"
  defp format_error(:invalid_fixture_state), do: "this fixture is not in an editable state"
  defp format_error(:participant_required), do: "choose the participant who was present"
  defp format_error(reason), do: inspect(reason)

  defp participant_label(participation), do: Competitions.participant_name(participation)
end
