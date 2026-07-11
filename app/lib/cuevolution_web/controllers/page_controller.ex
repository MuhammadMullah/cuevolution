defmodule CuevolutionWeb.PageController do
  use CuevolutionWeb, :controller

  alias Cuevolution.Accounts

  @doc "Sends visitors straight into the player app — signed in or not."
  def home(conn, _params) do
    destination =
      case get_session(conn, :player_token) do
        nil ->
          ~p"/login"

        token ->
          if Accounts.get_player_by_session_token(token), do: ~p"/fixtures", else: ~p"/login"
      end

    redirect(conn, to: destination)
  end
end
