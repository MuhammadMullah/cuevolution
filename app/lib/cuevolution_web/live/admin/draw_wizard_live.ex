defmodule CuevolutionWeb.Admin.DrawWizardLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Draw
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    stages = Enum.filter(Competitions.list_stages(), &(&1.name == "Grassroots"))
    venues = Venues.list_venues(active: true)

    {:ok,
     socket
     |> assign(
       page_title: "Run draw",
       stages: stages,
       venues: venues,
       categories: [{"Individual Male", "male"}, {"Individual Female", "female"}],
       stage: List.first(stages),
       proposal: nil,
       draw: nil,
       groups: [],
       form: to_form(%{}, as: :draw)
     )}
  end

  def handle_event("propose", %{"draw" => params}, socket) do
    with {:ok, stage} <- find_stage(socket.assigns.stages, params["stage_id"]),
         {:ok, venue} <- find_venue(socket.assigns.venues, params["venue_id"]),
         category when category in ~w(male female) <- params["category"],
         {:ok, proposal} <- Competitions.propose_draw(stage.id, venue.id, category) do
      {:noreply,
       socket
       |> assign(:stage, stage)
       |> assign(:proposal, proposal)
       |> assign(:form, to_form(params, as: :draw))}
    else
      {:error, :below_minimum} ->
        {:noreply,
         put_flash(socket, :error, "At least four verified entrants are required to run a draw.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a valid venue and category first.")}
    end
  end

  def handle_event("create_draw", %{"draw" => params}, socket) do
    with {:ok, stage} <- find_stage(socket.assigns.stages, params["stage_id"]),
         {:ok, venue} <- find_venue(socket.assigns.venues, params["venue_id"]),
         category when category in ~w(male female) <- params["category"],
         {:ok, draw} <-
           Competitions.create_draw(%{stage_id: stage.id, venue_id: venue.id, category: category}),
         {:ok, groups} <-
           Competitions.deal_draw(
             draw,
             socket.assigns.current_admin,
             parse_override(params["group_count"])
           ) do
      groups =
        Cuevolution.Repo.preload(groups,
          group_memberships: [stage_participation: [:player, :team]]
        )

      {:noreply,
       socket
       |> assign(:draw, Cuevolution.Repo.get!(Draw, draw.id))
       |> assign(:groups, groups)
       |> put_flash(:info, "Draw previewed. Review the groups before approving.")}
    else
      {:error, :below_minimum} ->
        {:noreply,
         put_flash(socket, :error, "At least four verified entrants are required to run a draw.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the draw: #{format_error(reason)}")}
    end
  end

  def handle_event("advance", %{"state" => state}, socket) do
    case Competitions.advance_draw_state(socket.assigns.draw, socket.assigns.current_admin, state) do
      {:ok, %{draw: draw}} when is_map(draw) ->
        {:noreply, assign(socket, :draw, draw)}

      {:ok, draw} ->
        {:noreply, assign(socket, :draw, draw)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Couldn't advance the draw: #{format_error(reason)}")}
    end
  end

  def handle_event("redraw", %{"reason" => reason}, socket) do
    case Competitions.redraw(socket.assigns.draw, socket.assigns.current_admin, reason) do
      {:ok, draw} ->
        {:noreply,
         socket
         |> assign(:draw, draw)
         |> assign(:groups, [])
         |> put_flash(:info, "A new draft draw was created.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't redraw: #{format_error(reason)}")}
    end
  end

  defp find_stage(stages, id) do
    case Enum.find(stages, &(&1.id == id)) do
      nil -> {:error, :stage_required}
      stage -> {:ok, stage}
    end
  end

  defp find_venue(venues, id) do
    case Enum.find(venues, &(&1.id == id)) do
      nil -> {:error, :venue_required}
      venue -> {:ok, venue}
    end
  end

  defp parse_override(nil), do: nil
  defp parse_override(""), do: nil

  defp parse_override(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp format_error(:invalid_group_count), do: "the group count is invalid"
  defp format_error(:already_dealt), do: "this draw has already been dealt"
  defp format_error(:unauthorized), do: "you do not have permission"
  defp format_error(reason), do: inspect(reason)
end
