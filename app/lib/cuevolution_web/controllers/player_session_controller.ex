defmodule CuevolutionWeb.PlayerSessionController do
  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts
  alias CuevolutionWeb.PlayerAuth

  def create(conn, %{"player" => %{"login" => login, "password" => password}}) do
    case Accounts.authenticate_player(login, password) do
      {:ok, player} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> PlayerAuth.log_in_player(player)
        |> redirect(to: ~p"/fixtures")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email/username or password")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> PlayerAuth.log_out_player()
    |> redirect(to: ~p"/login")
  end
end
