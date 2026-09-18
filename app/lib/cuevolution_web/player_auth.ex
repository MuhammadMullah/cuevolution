defmodule CuevolutionWeb.PlayerAuth do
  @moduledoc """
  Player authentication plugs and LiveView `on_mount` hook.

  Mirrors `CuevolutionWeb.AdminAuth` but reads the `:player_token` session
  key — entirely separate from the admin session (spec 001 FR-001/NFR-4.2).
  """

  use CuevolutionWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Cuevolution.Accounts
  alias Cuevolution.Teams

  @player_session_key :player_token

  @doc "Assigns `:current_player` from the session's player token, if any."
  def fetch_current_player(conn, _opts) do
    player =
      case get_session(conn, @player_session_key) do
        nil -> nil
        token -> Accounts.get_player_by_session_token(token)
      end

    assign(conn, :current_player, player)
  end

  @doc "Halts and redirects to the player login page unless `:current_player` is assigned."
  def require_player(conn, _opts) do
    if conn.assigns[:current_player] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc "Stores a new player session token and assigns `:current_player`."
  def log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)

    conn
    |> renew_session()
    |> put_session(@player_session_key, token)
    |> assign(:current_player, player)
  end

  @doc "Deletes the player session token and clears the session."
  def log_out_player(conn) do
    if token = get_session(conn, @player_session_key) do
      Accounts.delete_player_session_token(token)
    end

    conn
    |> renew_session()
    |> assign(:current_player, nil)
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  LiveView `on_mount` hook: same access rule as `require_player/2`, for
  player-only LiveViews. Also assigns `:pending_invitations` (the team-
  invitation banner's data, shown by `PlayerComponents.app_shell/1` on
  every player page) and attaches a shared `handle_event` hook for
  `"accept_invitation"`/`"decline_invitation"` — attached here rather than
  duplicated in every player LiveView's own `handle_event`, since every
  player LiveView already goes through this same `on_mount`.
  """
  def on_mount(:ensure_player, _params, session, socket) do
    player =
      case session["player_token"] do
        nil -> nil
        token -> Accounts.get_player_by_session_token(token)
      end

    if player do
      socket =
        socket
        |> Phoenix.Component.assign(:current_player, player)
        |> assign_pending_invitations(player)
        |> Phoenix.LiveView.attach_hook(
          :team_invitation_actions,
          :handle_event,
          &handle_invitation_event/3
        )

      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  defp assign_pending_invitations(socket, player) do
    Phoenix.Component.assign(
      socket,
      :pending_invitations,
      Teams.list_pending_invitations_for_player(player.id)
    )
  end

  defp handle_invitation_event("accept_invitation", %{"id" => id}, socket) do
    player = socket.assigns.current_player

    socket =
      case Teams.get_pending_invitation_for_player(id, player.id) do
        nil ->
          Phoenix.LiveView.put_flash(socket, :error, "That invitation is no longer available.")

        invitation ->
          case Teams.accept_invitation(invitation, player) do
            {:ok, _player} ->
              socket
              |> Phoenix.LiveView.put_flash(:info, "You joined the team!")
              |> Phoenix.LiveView.push_navigate(to: ~p"/team")

            {:error, :roster_frozen} ->
              Phoenix.LiveView.put_flash(
                socket,
                :error,
                "That team's roster is frozen and can no longer accept new players."
              )

            {:error, :roster_full} ->
              Phoenix.LiveView.put_flash(socket, :error, "That team's roster is already full.")

            {:error, :already_on_a_team} ->
              Phoenix.LiveView.put_flash(socket, :error, "You're already on a team.")

            {:error, _reason} ->
              Phoenix.LiveView.put_flash(
                socket,
                :error,
                "That invitation is no longer available."
              )
          end
      end

    {:halt, assign_pending_invitations(socket, player)}
  end

  defp handle_invitation_event("decline_invitation", %{"id" => id}, socket) do
    player = socket.assigns.current_player

    socket =
      case Teams.get_pending_invitation_for_player(id, player.id) do
        nil ->
          socket

        invitation ->
          case Teams.decline_invitation(invitation, player) do
            {:ok, _invitation} ->
              Phoenix.LiveView.put_flash(socket, :info, "Invitation declined.")

            {:error, _reason} ->
              Phoenix.LiveView.put_flash(
                socket,
                :error,
                "That invitation is no longer available."
              )
          end
      end

    {:halt, assign_pending_invitations(socket, player)}
  end

  defp handle_invitation_event(_event, _params, socket), do: {:cont, socket}
end
