defmodule CuevolutionWeb.PlayerDetailLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

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
     assign(socket, page_title: "Player Detail", player: player, notifications: notifications)}
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
