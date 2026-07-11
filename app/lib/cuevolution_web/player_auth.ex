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

  @doc "LiveView `on_mount` hook: same access rule as `require_player/2`, for player-only LiveViews."
  def on_mount(:ensure_player, _params, session, socket) do
    player =
      case session["player_token"] do
        nil -> nil
        token -> Accounts.get_player_by_session_token(token)
      end

    if player do
      {:cont, Phoenix.Component.assign(socket, :current_player, player)}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end
end
