defmodule CuevolutionWeb.ResetPasswordLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias CuevolutionWeb.PlayerComponents

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_player_by_reset_password_token(token) do
      %Player{} = player ->
        {:ok,
         assign(socket,
           page_title: "Reset Password",
           stage: :form,
           player: player,
           form: to_form(Player.reset_password_changeset(player, %{}), as: :player)
         )}

      nil ->
        {:ok, assign(socket, page_title: "Reset Password", stage: :invalid)}
    end
  end

  def handle_event("reset_password", %{"player" => params}, socket) do
    case Accounts.reset_player_password(socket.assigns.player, params) do
      {:ok, _player} ->
        {:noreply, assign(socket, stage: :done)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :player))}
    end
  end
end
