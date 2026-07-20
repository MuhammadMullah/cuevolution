defmodule CuevolutionWeb.PlayerDetailLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  def mount(%{"id" => id}, _session, socket) do
    player = Player |> Repo.get!(id) |> Repo.preload(:region)

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
       anonymize_warnings: nil
     )}
  end

  def handle_event("confirm_anonymize", _params, socket) do
    {:noreply,
     assign(socket, :anonymize_warnings, Accounts.anonymize_warnings(socket.assigns.player))}
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

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't anonymize this player.")}
    end
  end

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
