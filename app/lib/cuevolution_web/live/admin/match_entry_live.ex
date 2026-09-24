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
       frame_winners: %{},
       correction_winners: %{},
       selected_present: nil
     )
     |> load_fixture(id)}
  end

  def handle_event("set_frame", %{"sequence" => sequence, "winner" => winner}, socket) do
    {:noreply, update(socket, :frame_winners, &Map.put(&1, sequence, winner))}
  end

  def handle_event(
        "set_correction_frame",
        %{"sequence" => sequence, "winner" => winner},
        socket
      ) do
    {:noreply, update(socket, :correction_winners, &Map.put(&1, sequence, winner))}
  end

  def handle_event("record_frames", _params, socket) do
    winners = frame_list(socket.assigns.frame_winners)

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
    corrections = correction_diff(socket.assigns)

    case Competitions.verify_result(
           socket.assigns.fixture,
           socket.assigns.current_admin,
           corrections
         ) do
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
      correction_winners: recorded_frame_winners(fixture)
    )
  end

  defp reload_fixture(socket, message) do
    socket
    |> load_fixture(socket.assigns.fixture.id)
    |> assign(:frame_winners, %{})
    |> put_flash(:info, message)
  end

  # Rebuilds "sequence" => "a"/"b" from the persisted MatchFrame rows so the
  # verify panel's frame strip starts pre-filled with what the rep actually
  # recorded — the TD is correcting a real, visible record, not typing blind.
  defp recorded_frame_winners(%Fixture{result: %{match_frames: frames}})
       when is_list(frames) and frames != [] do
    Map.new(frames, fn frame ->
      side = if frame.winner_player_id == frame.home_player_id, do: "a", else: "b"
      {to_string(frame.sequence), side}
    end)
  end

  defp recorded_frame_winners(_fixture), do: %{}

  defp frame_list(winners_map) do
    Enum.map(1..5, &Map.get(winners_map, to_string(&1)))
  end

  # Only sends a correction to `verify_result/3` when the TD actually
  # changed something from what was recorded — an unmodified verify stays a
  # plain verify, not a no-op "correction" that would still churn through
  # `maybe_replace_structured_frames/3`.
  defp correction_diff(%{fixture: fixture, correction_winners: winners}) do
    original = recorded_frame_winners(fixture)
    if winners == original, do: nil, else: frame_list(winners)
  end

  @doc "Tallies a's/b's frame-winner map into a live \"3–1\" style score string."
  def score_tally(winners_map) do
    values = Map.values(winners_map)
    a = Enum.count(values, &(&1 == "a"))
    b = Enum.count(values, &(&1 == "b"))
    "#{a}–#{b}"
  end

  defp format_error(:five_frames_required), do: "exactly five frame winners are required"
  defp format_error(:no_majority), do: "one participant must win at least three frames"
  defp format_error(:reason_required), do: "a reason is required"
  defp format_error(:invalid_fixture_state), do: "this fixture is not in an editable state"
  defp format_error(:participant_required), do: "choose the participant who was present"
  defp format_error(reason), do: inspect(reason)

  defp participant_label(participation), do: Competitions.participant_name(participation)
end
