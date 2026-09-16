defmodule CuevolutionWeb.PlayerDetailLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  def mount(%{"id" => id}, _session, socket) do
    player = Player |> Repo.get!(id) |> Repo.preload([:region, :preferred_venue])

    notifications =
      Notification
      |> where(player_id: ^id)
      |> order_by(desc: :inserted_at)
      |> limit(10)
      |> Repo.all()

    {:ok,
     assign(socket,
       page_title: "Player Detail",
       player: player,
       notifications: notifications,
       anonymize_warnings: nil,
       editing_venue: false,
       venue_options: [],
       venue_form_id: nil
     )}
  end

  def handle_event("confirm_anonymize", _params, socket) do
    if Admin.can?(socket.assigns.current_admin, :anonymize_users) do
      {:noreply,
       assign(socket, :anonymize_warnings, Accounts.anonymize_warnings(socket.assigns.player))}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to anonymize users.")}
    end
  end

  def handle_event("cancel_anonymize", _params, socket) do
    {:noreply, assign(socket, :anonymize_warnings, nil)}
  end

  def handle_event("anonymize", _params, socket) do
    case Accounts.anonymize_player(socket.assigns.player, socket.assigns.current_admin) do
      {:ok, player} ->
        {:noreply,
         socket
         |> assign(player: player, anonymize_warnings: nil)
         |> put_flash(:info, "Player anonymized.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to anonymize users.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't anonymize this player.")}
    end
  end

  def handle_event("request_edit_venue", _params, socket) do
    if Admin.can?(socket.assigns.current_admin, :manage_players) do
      player = socket.assigns.player

      {:noreply,
       assign(socket,
         editing_venue: true,
         venue_options: Venues.list_active_for_region(player.region_id),
         venue_form_id: player.preferred_venue_id
       )}
    else
      {:noreply,
       put_flash(socket, :error, "You don't have permission to change a player's venue.")}
    end
  end

  def handle_event("cancel_edit_venue", _params, socket) do
    {:noreply, assign(socket, editing_venue: false, venue_options: [], venue_form_id: nil)}
  end

  def handle_event("save_venue", %{"venue_id" => venue_id}, socket) do
    case Accounts.admin_change_venue(
           socket.assigns.player,
           venue_id,
           socket.assigns.current_admin
         ) do
      {:ok, player} ->
        player = Repo.preload(player, [:region, :preferred_venue], force: true)

        {:noreply,
         socket
         |> assign(player: player, editing_venue: false, venue_options: [], venue_form_id: nil)
         |> put_flash(:info, "Venue updated.")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, "You don't have permission to change a player's venue.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update this player's venue.")}
    end
  end

  defp venue_label(nil), do: "Not set"
  defp venue_label(%{active: true, name: name}), do: name
  defp venue_label(%{active: false, name: name}), do: "#{name} (inactive)"

  defp player_fields(player) do
    [
      {"Email", player.email},
      {"Mobile", player.mobile_number},
      {"Location", player.location},
      {"Country", player.country},
      {"Category", String.capitalize(player.gender || "")},
      {"Notification preference", String.capitalize(player.notification_preference || "")},
      {"Registered", player.inserted_at}
    ]
  end
end
