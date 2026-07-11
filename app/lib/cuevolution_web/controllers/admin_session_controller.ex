defmodule CuevolutionWeb.AdminSessionController do
  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts
  alias CuevolutionWeb.AdminAuth

  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_admin(email, password) do
      {:ok, admin} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> AdminAuth.log_in_admin(admin)
        |> redirect(to: ~p"/admin/dashboard")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/admin/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> AdminAuth.log_out_admin()
    |> redirect(to: ~p"/admin/login")
  end
end
