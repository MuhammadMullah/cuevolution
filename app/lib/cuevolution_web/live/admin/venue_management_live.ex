defmodule CuevolutionWeb.VenueManagementLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue

  def mount(_params, _session, socket) do
    regions = Repo.all(from r in Region, order_by: r.name)

    {:ok,
     socket
     |> assign(page_title: "Venue Management", regions: regions, filter_region_id: nil)
     |> assign(editing_venue: nil, filter_form: to_form(%{}, as: :filter))
     |> assign_form(Venue.changeset(%Venue{}, %{}))
     |> load_venues()}
  end

  def handle_event("filter", %{"filter" => %{"region_id" => region_id}}, socket) do
    region_id = if region_id == "", do: nil, else: region_id

    {:noreply,
     socket
     |> assign(filter_form: to_form(%{"region_id" => region_id}, as: :filter))
     |> assign(:filter_region_id, region_id)
     |> load_venues()}
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
    result =
      if venue = socket.assigns.editing_venue do
        Venues.update_venue(venue, params)
      else
        Venues.create_venue(params)
      end

    case result do
      {:ok, _venue} ->
        {:noreply,
         socket
         |> put_flash(:info, "Venue saved.")
         |> assign(:editing_venue, nil)
         |> assign_form(Venue.changeset(%Venue{}, %{}))
         |> load_venues()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    venue = Repo.get!(Venue, id)
    {:ok, _venue} = Venues.deactivate_venue(venue)

    {:noreply,
     socket
     |> put_flash(:info, "Venue deactivated.")
     |> load_venues()}
  end

  defp load_venues(socket) do
    filters =
      case socket.assigns.filter_region_id do
        nil -> %{}
        region_id -> %{region_id: region_id}
      end

    assign(socket, :venues, Venues.list_venues(filters))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :venue))
  end
end
