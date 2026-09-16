defmodule CuevolutionWeb.VenueManagementLive do
  @moduledoc """
  Admin "Venues" page (project-scope/Quevolution/Cuevolution Admin.dc.html) —
  one region in view at a time via tabs (never "all regions"), scoped
  add/rename/activate/deactivate, plus the region's free-text "Other" venue
  submissions from registration (`Player.other_venue_name`) with a one-click
  promote into the real venue list.
  """
  use CuevolutionWeb, :live_view

  require Logger

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Competitions
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue
  alias CuevolutionWeb.AdminComponents

  def mount(params, _session, socket) do
    regions = Accounts.list_regions()
    region = Enum.find(regions, &(&1.id == params["region_id"])) || List.first(regions)

    {:ok,
     socket
     |> assign(page_title: "Venue Management", regions: regions, region: region)
     |> assign(:editing_venue, nil)
     |> assign_form(Venue.changeset(%Venue{}, %{}))
     |> clear_deactivation_state()
     |> load_venues()
     |> load_custom_venues()}
  end

  def handle_event("select_region", %{"id" => region_id}, socket) do
    region = Enum.find(socket.assigns.regions, &(&1.id == region_id))

    {:noreply,
     socket
     |> assign(:region, region)
     |> assign(:editing_venue, nil)
     |> assign_form(Venue.changeset(%Venue{}, %{}))
     |> clear_deactivation_state()
     |> load_venues()
     |> load_custom_venues()}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    venue = Repo.get!(Venue, id)

    {:noreply,
     socket
     |> assign(:editing_venue, venue)
     |> assign_form(Venue.changeset(venue, %{}))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_venue, nil)
     |> assign_form(Venue.changeset(%Venue{}, %{}))}
  end

  def handle_event("validate", %{"venue" => params}, socket) do
    changeset =
      (socket.assigns.editing_venue || %Venue{})
      |> Venue.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"venue" => params}, socket) do
    params = Map.put(params, "region_id", socket.assigns.region.id)

    result =
      if venue = socket.assigns.editing_venue do
        Venues.update_venue(venue, params)
      else
        Venues.create_venue(params)
      end

    case result do
      {:ok, venue} ->
        verb = if socket.assigns.editing_venue, do: "updated", else: "added to"

        {:noreply,
         socket
         |> put_flash(:info, "\"#{venue.name}\" #{verb} #{socket.assigns.region.name}.")
         |> assign(:editing_venue, nil)
         |> assign_form(Venue.changeset(%Venue{}, %{}))
         |> load_venues()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("request_deactivate", %{"id" => id}, socket) do
    if Admin.can?(socket.assigns.current_admin, :manage_venues) do
      venue = Repo.get!(Venue, id)

      {:noreply,
       assign(socket,
         deactivating_venue: venue,
         deactivate_blocked?: Competitions.venue_has_draws?(venue.id),
         suggestion_options: Venues.list_active_venues_in_region(venue.region_id, venue.id),
         selected_suggestion_ids: []
       )}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to deactivate venues.")}
    end
  end

  def handle_event("toggle_suggestion", %{"id" => id}, socket) do
    selected = socket.assigns.selected_suggestion_ids
    updated = if id in selected, do: List.delete(selected, id), else: [id | selected]

    {:noreply, assign(socket, :selected_suggestion_ids, updated)}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, clear_deactivation_state(socket)}
  end

  def handle_event("confirm_deactivate", _params, socket) do
    venue = socket.assigns.deactivating_venue
    suggested_ids = socket.assigns.selected_suggestion_ids

    case Venues.deactivate_venue(venue, suggested_ids) do
      {:ok, venue} ->
        notify_affected_players(venue)

        {:noreply,
         socket
         |> put_flash(:info, "\"#{venue.name}\" deactivated.")
         |> clear_deactivation_state()
         |> load_venues()}

      {:error, :draws_exist} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "\"#{venue.name}\" can't be deactivated — draws already exist for it."
         )
         |> clear_deactivation_state()
         |> load_venues()}
    end
  end

  def handle_event("activate", %{"id" => id}, socket) do
    venue = Repo.get!(Venue, id)
    {:ok, _venue} = Venues.activate_venue(venue)

    {:noreply, socket |> put_flash(:info, "\"#{venue.name}\" reactivated.") |> load_venues()}
  end

  def handle_event("promote", %{"name" => name}, socket) do
    case Venues.create_venue(%{"name" => name, "region_id" => socket.assigns.region.id}) do
      {:ok, venue} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{venue.name}\" added to #{socket.assigns.region.name}.")
         |> load_venues()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A venue named \"#{name}\" already exists in #{socket.assigns.region.name}."
         )}
    end
  end

  defp clear_deactivation_state(socket) do
    assign(socket,
      deactivating_venue: nil,
      deactivate_blocked?: false,
      suggestion_options: [],
      selected_suggestion_ids: []
    )
  end

  defp notify_affected_players(venue) do
    suggested_names =
      venue.id
      |> Venues.list_suggestions_for_venue()
      |> Enum.map(& &1.name)

    payload = %{venue_name: venue.name, suggested_venues: suggested_names}

    venue.id
    |> Accounts.list_players_by_preferred_venue()
    |> Repo.all()
    |> Enum.each(&dispatch_venue_deactivated(&1, payload))
  end

  defp dispatch_venue_deactivated(player, payload) do
    Notifications.dispatch(player, :venue_deactivated, payload)
  rescue
    error ->
      Logger.error(
        "venue_deactivated dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end

  defp load_venues(socket) do
    assign(socket, :venues, Venues.list_venues(%{region_id: socket.assigns.region.id}))
  end

  defp load_custom_venues(socket) do
    assign(
      socket,
      :custom_venue_submissions,
      Accounts.list_custom_venue_submissions(socket.assigns.region.id)
    )
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :venue))
  end
end
