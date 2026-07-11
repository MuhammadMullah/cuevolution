defmodule CuevolutionWeb.TeamCreationLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Teams
  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    if socket.assigns.current_player.team_id do
      {:ok, push_navigate(socket, to: ~p"/team")}
    else
      {:ok, assign(socket, page_title: "Create a Team", form: to_form(%{}, as: :team))}
    end
  end

  def handle_event("save", %{"team" => params}, socket) do
    case Teams.create_team(socket.assigns.current_player, params) do
      {:ok, _team} ->
        {:noreply,
         socket
         |> put_flash(:info, "Team created — you're the captain.")
         |> push_navigate(to: ~p"/team")}

      {:error, :already_on_a_team} ->
        {:noreply, put_flash(socket, :error, "You're already on a team.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :team))}
    end
  end
end
