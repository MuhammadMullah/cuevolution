defmodule CuevolutionWeb.AdminAuth do
  @moduledoc """
  Admin authentication plugs and LiveView `on_mount` hook.

  Admin sessions are entirely distinct from player sessions (spec 001 FR-001):
  a player's `:player_token` session key is never inspected here, so a
  player-authenticated request is treated identically to an anonymous one.
  """

  use CuevolutionWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Cuevolution.Accounts

  @admin_session_key :admin_token

  @doc "Assigns `:current_admin` from the session's admin token, if any."
  def fetch_current_admin(conn, _opts) do
    admin =
      case get_session(conn, @admin_session_key) do
        nil -> nil
        token -> Accounts.get_admin_by_session_token(token)
      end

    assign(conn, :current_admin, admin)
  end

  @doc "Halts and redirects to the admin login page unless `:current_admin` is assigned."
  def require_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in as an admin to access this page.")
      |> redirect(to: ~p"/admin/login")
      |> halt()
    end
  end

  @doc "Stores a new admin session token and assigns `:current_admin`."
  def log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)

    conn
    |> renew_session()
    |> put_session(@admin_session_key, token)
    |> assign(:current_admin, admin)
  end

  @doc "Deletes the admin session token and clears the session."
  def log_out_admin(conn) do
    if token = get_session(conn, @admin_session_key) do
      Accounts.delete_admin_session_token(token)
    end

    conn
    |> renew_session()
    |> assign(:current_admin, nil)
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc "LiveView `on_mount` hook: same access rule as `require_admin/2`, for admin-only LiveViews."
  def on_mount(:ensure_admin, _params, session, socket) do
    admin =
      case session["admin_token"] do
        nil -> nil
        token -> Accounts.get_admin_by_session_token(token)
      end

    if admin do
      {:cont, Phoenix.Component.assign(socket, :current_admin, admin)}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in as an admin to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin/login")

      {:halt, socket}
    end
  end

  # Halts unless `:current_admin` (already assigned by `:ensure_admin`, which
  # must run first) has the `"super_admin"` role — for the admin-management
  # page, which only a super admin may reach.
  @doc false
  def on_mount(:ensure_super_admin, _params, _session, socket) do
    if socket.assigns.current_admin.role == "super_admin" do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have access to that page.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin/dashboard")

      {:halt, socket}
    end
  end
end
