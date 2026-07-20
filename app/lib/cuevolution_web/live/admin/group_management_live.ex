defmodule CuevolutionWeb.GroupManagementLive do
  @moduledoc """
  Admin "Groups" page (spec 006) — Grassroots/Regional stage + region +
  category tabs, create groups, assign unassigned participants into them.
  Grassroots groups are additionally scoped to a venue within the selected
  region (venue-scoped pairing, FR-003); Regional groups are region-scoped
  only (FR-004). Neither stage ever creates a knockout bracket — those are
  Circuit/Finals stage+category constructs (`Competitions.ensure_knockout_bracket/2`),
  unrelated to groups.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  @categories ~w(male female team)

  def mount(_params, _session, socket) do
    stages =
      Competitions.list_stages() |> Enum.filter(&(&1.name in ["Grassroots", "Regional"]))

    regions = Accounts.list_regions()
    stage = List.first(stages)
    region = List.first(regions)

    {:ok,
     socket
     |> assign(
       page_title: "Groups",
       stages: stages,
       regions: regions,
       categories: @categories,
       stage: stage,
       region: region,
       category: List.first(@categories),
       venue: nil,
       form: to_form(%{}, as: :group)
     )
     |> load_venues()
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> load_venues()
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_region", %{"id" => id}, socket) do
    region = Enum.find(socket.assigns.regions, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:region, region)
     |> load_venues()
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:category, category)
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_venue", %{"id" => id}, socket) do
    venue = Enum.find(socket.assigns.venues, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:venue, venue)
     |> load_groups()}
  end

  def handle_event("create_group", %{"group" => %{"name" => name}}, socket) do
    attrs = %{
      stage_id: socket.assigns.stage.id,
      region_id: socket.assigns.region.id,
      venue_id: if(grassroots?(socket) && socket.assigns.venue, do: socket.assigns.venue.id),
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
  end

  def handle_event(
        "assign_to_group",
        %{"group_id" => group_id, "participation_id" => pid},
        socket
      ) do
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
  end

  defp grassroots?(socket), do: socket.assigns.stage.name == "Grassroots"

  defp scope_label(assigns) do
    venue_or_region =
      if assigns.stage.name == "Grassroots" && assigns.venue,
        do: assigns.venue.name,
        else: assigns.region.name

    "#{assigns.stage.name} · #{venue_or_region} · #{category_label(assigns.category)}"
  end

  defp category_label("male"), do: "Individual Male"
  defp category_label("female"), do: "Individual Female"
  defp category_label("team"), do: "Teams"

  defp load_venues(socket) do
    if grassroots?(socket) do
      venues = Venues.list_active_for_region(socket.assigns.region.id)
      assign(socket, venues: venues, venue: List.first(venues))
    else
      assign(socket, venues: [], venue: nil)
    end
  end

  defp load_groups(socket) do
    scope =
      if grassroots?(socket) && socket.assigns.venue do
        {:venue_id, socket.assigns.venue.id}
      else
        {:region_id, socket.assigns.region.id}
      end

    assign(
      socket,
      :groups,
      if(grassroots?(socket) && is_nil(socket.assigns.venue),
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

  defp participant_name(%{player_id: nil, team: team}), do: team.name
  defp participant_name(%{player: player}), do: "#{player.first_name} #{player.last_name}"

  # Matches CuevolutionWeb.PlayerComponents' @stage_styles palette (the
  # actual app design system — gray/Kenya-Green/Kenya-Red/ink-950), not the
  # Grassroots/Regional colors in the reference mockup's latest revision.
  defp stage_tab_active_class("Grassroots"), do: "border-ink-500 bg-ink-100 text-ink-700"
  defp stage_tab_active_class("Regional"), do: "border-green-500 bg-green-100 text-green-700"
  defp stage_tab_active_class(_stage), do: "border-red-500 bg-red-50 text-red-700"
end
