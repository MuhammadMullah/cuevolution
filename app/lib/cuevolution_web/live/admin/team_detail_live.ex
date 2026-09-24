defmodule CuevolutionWeb.TeamDetailLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  def mount(%{"id" => id}, _session, socket) do
    team = Team |> Repo.get!(id) |> Repo.preload([:region, :captain, roster: []])

    {:ok,
     socket
     |> assign(
       page_title: "Team Detail",
       add_form: to_form(%{}, as: :roster),
       player_suggestions: [],
       selected_player: nil
     )
     |> assign_team(team)}
  end

  def handle_event("search_players", %{"value" => query}, socket) do
    {:noreply,
     assign(socket, :player_suggestions, Accounts.search_players_for_team_invite(query))}
  end

  def handle_event("select_player", %{"id" => id}, socket) do
    case fetch_player(id) do
      %Player{} = player ->
        {:noreply,
         assign(socket,
           add_form: to_form(%{"player_id" => player.id}, as: :roster),
           selected_player: player,
           player_suggestions: []
         )}

      nil ->
        {:noreply, put_flash(socket, :error, "That player is no longer available.")}
    end
  end

  def handle_event("add_player", %{"roster" => %{"player_id" => player_id}}, socket) do
    with %Player{} = player <- fetch_player(player_id),
         {:ok, _player} <-
           Teams.admin_add_player_to_team(
             socket.assigns.current_admin,
             socket.assigns.team,
             player
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Player added directly to the team.")
       |> assign(
         add_form: to_form(%{}, as: :roster),
         selected_player: nil,
         player_suggestions: []
       )
       |> reload_team()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That player is no longer available.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to manage teams.")}

      {:error, :already_on_a_team} ->
        {:noreply, put_flash(socket, :error, "That player is already on a team.")}

      {:error, :roster_full} ->
        {:noreply, put_flash(socket, :error, "The roster is full (max 8).")}

      {:error, :roster_frozen} ->
        {:noreply, put_flash(socket, :error, "The roster is frozen.")}

      {:error, :registration_closed} ->
        {:noreply,
         put_flash(socket, :error, "That player is registered for the next tournament season.")}
    end
  end

  def handle_event("delete_team", _params, socket) do
    case Teams.admin_delete_team(socket.assigns.current_admin, socket.assigns.team) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Team deleted.")
         |> push_navigate(to: ~p"/admin/players")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to manage teams.")}

      {:error, :roster_frozen} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This team has already been drawn into a stage and can no longer be deleted."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't delete this team.")}
    end
  end

  defp assign_team(socket, team) do
    assign(socket, team: team, eligible: Teams.eligible?(team))
  end

  defp reload_team(socket) do
    team =
      Team |> Repo.get!(socket.assigns.team.id) |> Repo.preload([:region, :captain, roster: []])

    assign_team(socket, team)
  end

  defp fetch_player(id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id), do: Repo.get(Player, id)
  end
end
