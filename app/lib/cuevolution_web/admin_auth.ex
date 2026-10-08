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
  alias Cuevolution.Accounts.Admin

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
      socket =
        socket
        |> Phoenix.Component.assign(:current_admin, admin)
        |> Phoenix.LiveView.attach_hook(
          :force_password_change,
          :handle_event,
          &handle_forced_password_change/3
        )

      {:cont, socket}
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

  @doc "LiveView hook for role-based admin routes. Each event still re-checks permissions before mutation."
  def on_mount({:ensure_permission, permission}, _params, _session, socket) do
    if Admin.can?(socket.assigns.current_admin, permission) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You don't have access to that page.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin/dashboard")

      {:halt, socket}
    end
  end

  # Attached to every admin LiveView mount (see :ensure_admin above) so the
  # "set a new password" modal (CuevolutionWeb.AdminComponents.app_shell/1,
  # shown whenever `current_admin.must_change_password` is true) works
  # without every single admin LiveView needing its own handle_event clause
  # for it. Falls through to the LiveView's own handlers for every other
  # event.
  defp handle_forced_password_change("change_forced_password", %{"admin" => params}, socket) do
    case Accounts.change_own_password(socket.assigns.current_admin, params) do
      {:ok, admin} ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_admin, admin)
          |> Phoenix.LiveView.put_flash(:info, "Password updated.")

        {:halt, socket}

      {:error, changeset} ->
        {:halt, Phoenix.LiveView.put_flash(socket, :error, password_error_message(changeset))}
    end
  end

  defp handle_forced_password_change(_event, _params, socket), do: {:cont, socket}

  defp password_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join("; ")
  end
end
