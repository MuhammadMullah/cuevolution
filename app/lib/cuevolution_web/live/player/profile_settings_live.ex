defmodule CuevolutionWeb.ProfileSettingsLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Repo
  alias CuevolutionWeb.PlayerComponents

  @notification_defs [
    {"email", "Email", "Confirmations and draws by email."},
    {"sms", "SMS", "Text messages to your mobile."},
    {"both", "Both", "Email and SMS — never miss a draw."}
  ]

  def mount(_params, _session, socket) do
    player = Repo.preload(socket.assigns.current_player, [:region, :preferred_venue, :team])

    {:ok,
     assign(socket,
       page_title: "Profile Settings",
       current_player: player,
       notification_defs: @notification_defs,
       saved_message: nil
     )}
  end

  def handle_event("set_notification_preference", %{"choice" => preference}, socket) do
    case Accounts.update_notification_preference(socket.assigns.current_player, preference) do
      {:ok, player} ->
        {:noreply,
         assign(socket,
           current_player: player,
           saved_message: "Notification preference saved."
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update preference.")}
    end
  end

  defp team_label(nil), do: "No team yet"
  defp team_label(team), do: team.name

  defp profile_rows(player) do
    [
      {"Username", "@#{player.username}"},
      {"Category", String.capitalize(player.gender)},
      {"Date of birth", Calendar.strftime(player.date_of_birth, "%-d %b %Y")},
      {"Region", player.region.name},
      {"Preferred venue", preferred_venue_label(player)},
      {"Email", player.email},
      {"Mobile", player.mobile_number},
      {"Town", player.location}
    ]
  end

  defp preferred_venue_label(%{preferred_venue: %{name: name}}), do: name
  defp preferred_venue_label(%{other_venue_name: name}) when is_binary(name), do: name
  defp preferred_venue_label(_player), do: "Not set"
end
