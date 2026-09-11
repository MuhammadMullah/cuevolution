defmodule CuevolutionWeb.ProfileSettingsLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.PlayerComponents

  @notification_defs [
    {"email", "Email", "Confirmations and draws by email."},
    {"sms", "SMS", "Text messages to your mobile."},
    {"both", "Both", "Email and SMS — never miss a draw."}
  ]

  @deactivate_phrase "DEACTIVATE"

  def mount(_params, _session, socket) do
    player = Repo.preload(socket.assigns.current_player, [:region, :preferred_venue, :team])

    {:ok,
     assign(socket,
       current_player: player,
       notification_defs: @notification_defs,
       saved_message: nil,
       region_locked?: Accounts.region_locked?(player),
       regions: Accounts.list_regions(),
       draft_region_id: player.region_id,
       draft_venue_id: player.preferred_venue_id,
       region_venues: Venues.list_active_for_region(player.region_id),
       venue_choice_pending?: is_nil(player.preferred_venue_id),
       password_form: to_form(Player.update_password_changeset(player, %{}), as: :player),
       editing_personal_details?: false,
       personal_details_form:
         to_form(Player.personal_details_changeset(player, %{}), as: :player),
       deactivate_modal_open?: false,
       deactivate_confirmation_text: "",
       deactivate_warnings: nil,
       deactivate_phrase: @deactivate_phrase
     )}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, page_title: page_title(socket.assigns.live_action))}
  end

  defp page_title(:settings), do: "Settings"
  defp page_title(_), do: "Profile"

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

  def handle_event("update_password", %{"player" => params}, socket) do
    case Accounts.update_player_password(socket.assigns.current_player, params) do
      {:ok, player} ->
        {:noreply,
         assign(socket,
           current_player: player,
           password_form: to_form(Player.update_password_changeset(player, %{}), as: :player),
           saved_message: "Password updated."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :player))}
    end
  end

  def handle_event("draft_region", %{"region_id" => region_id}, socket) do
    player = socket.assigns.current_player
    same_region? = region_id == player.region_id

    {:noreply,
     assign(socket,
       draft_region_id: region_id,
       region_venues: Venues.list_active_for_region(region_id),
       draft_venue_id: if(same_region?, do: player.preferred_venue_id, else: nil),
       venue_choice_pending?: not same_region?
     )}
  end

  def handle_event("draft_venue", %{"venue_id" => venue_id}, socket) do
    {:noreply, assign(socket, :draft_venue_id, venue_id)}
  end

  def handle_event("save_location", %{"region_id" => region_id, "venue_id" => venue_id}, socket) do
    player = socket.assigns.current_player

    result =
      if region_id == player.region_id do
        Accounts.change_venue(player, venue_id)
      else
        Accounts.change_region_and_venue(player, region_id, venue_id)
      end

    case result do
      {:ok, player} ->
        player = Repo.preload(player, [:region, :preferred_venue, :team], force: true)

        {:noreply,
         assign(socket,
           current_player: player,
           draft_region_id: player.region_id,
           draft_venue_id: player.preferred_venue_id,
           region_venues: Venues.list_active_for_region(player.region_id),
           venue_choice_pending?: false,
           saved_message: "Location updated."
         )}

      {:error, :region_locked} ->
        {:noreply,
         socket
         |> assign(:region_locked?, true)
         |> put_flash(:error, "Your region is locked — you've already played a match.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update your venue.")}
    end
  end

  def handle_event("toggle_personal_edit", _params, socket) do
    editing? = not socket.assigns.editing_personal_details?
    player = socket.assigns.current_player

    {:noreply,
     assign(socket,
       editing_personal_details?: editing?,
       personal_details_form: to_form(Player.personal_details_changeset(player, %{}), as: :player)
     )}
  end

  def handle_event("validate_personal_details", %{"player" => params}, socket) do
    changeset =
      socket.assigns.current_player
      |> Player.personal_details_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :personal_details_form, to_form(changeset, as: :player))}
  end

  def handle_event("save_personal_details", %{"player" => params}, socket) do
    case Accounts.update_personal_details(socket.assigns.current_player, params) do
      {:ok, player} ->
        {:noreply,
         assign(socket,
           current_player: player,
           editing_personal_details?: false,
           saved_message: "Profile updated."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :personal_details_form, to_form(changeset, as: :player))}
    end
  end

  def handle_event("open_deactivate_modal", _params, socket) do
    {:noreply,
     assign(socket,
       deactivate_modal_open?: true,
       deactivate_confirmation_text: "",
       deactivate_warnings: Accounts.anonymize_warnings(socket.assigns.current_player)
     )}
  end

  def handle_event("close_deactivate_modal", _params, socket) do
    {:noreply, assign(socket, deactivate_modal_open?: false, deactivate_confirmation_text: "")}
  end

  def handle_event("validate_deactivate_confirmation", %{"confirmation" => text}, socket) do
    {:noreply, assign(socket, :deactivate_confirmation_text, text)}
  end

  def handle_event("deactivate_account", %{"confirmation" => text}, socket) do
    if text == @deactivate_phrase do
      case Accounts.deactivate_player(socket.assigns.current_player) do
        {:ok, _player} ->
          {:noreply,
           socket
           |> put_flash(:info, "Your account has been deactivated.")
           |> redirect(to: ~p"/login")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't deactivate your account.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("change_venue", %{"venue_id" => venue_id}, socket) do
    case Accounts.change_venue(socket.assigns.current_player, venue_id) do
      {:ok, player} ->
        player = Repo.preload(player, [:region, :preferred_venue, :team], force: true)

        {:noreply,
         assign(socket,
           current_player: player,
           draft_venue_id: player.preferred_venue_id,
           saved_message: "Venue updated."
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update your venue.")}
    end
  end

  defp team_label(nil), do: "No team yet"
  defp team_label(team), do: team.name

  defp profile_rows(player) do
    [
      {"Username", "@#{player.username}"},
      {"Category", String.capitalize(player.gender)},
      {"Date of birth", Calendar.strftime(player.date_of_birth, "%-d %b %Y")},
      {"Email", player.email},
      {"Mobile", player.mobile_number},
      {"Town", player.location}
    ]
  end

  defp username_hint(nil, _player), do: {"neutral", nil}
  defp username_hint("", _player), do: {"neutral", nil}

  defp username_hint(username, player) do
    cond do
      String.downcase(username) == String.downcase(player.username) -> {"neutral", nil}
      Accounts.username_taken?(username) -> {"danger", "#{username} is already taken"}
      true -> {"success", "✓ #{username} is available"}
    end
  end

  defp age_hint(nil), do: nil
  defp age_hint(""), do: nil

  defp age_hint(dob_string) do
    case Date.from_iso8601(dob_string) do
      {:ok, dob} -> format_age_hint(age_in_years(dob))
      _ -> nil
    end
  end

  defp age_in_years(dob) do
    today = Date.utc_today()
    age = today.year - dob.year
    if {today.month, today.day} < {dob.month, dob.day}, do: age - 1, else: age
  end

  defp format_age_hint(age) when age < 0, do: nil
  defp format_age_hint(age) when age < 18, do: "Age #{age} — must be 18+"
  defp format_age_hint(age), do: "Age #{age}"
end
