defmodule CuevolutionWeb.Admin.TeamCreationLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create Team",
       form: to_form(%{}, as: :team),
       captain_suggestions: [],
       player_suggestions: [],
       captain: nil,
       selected_players: []
     )}
  end

  def handle_event("search_players", %{"kind" => kind, "value" => query}, socket)
      when kind in ["captain", "player"] do
    suggestions = Accounts.search_players_for_team_invite(query)

    {:noreply,
     assign(socket,
       captain_suggestions: if(kind == "captain", do: suggestions, else: []),
       player_suggestions: if(kind == "player", do: suggestions, else: [])
     )}
  end

  def handle_event("select_captain", %{"id" => id}, socket) do
    case fetch_player(id) do
      %Player{} = captain ->
        selected_players = add_player(socket.assigns.selected_players, captain)

        {:noreply,
         assign(socket,
           captain: captain,
           selected_players: selected_players,
           captain_suggestions: []
         )}

      nil ->
        {:noreply, put_flash(socket, :error, "That captain is no longer available.")}
    end
  end

  def handle_event("select_player", %{"id" => id}, socket) do
    case fetch_player(id) do
      %Player{} = player ->
        {:noreply,
         assign(socket,
           selected_players: add_player(socket.assigns.selected_players, player),
           player_suggestions: []
         )}

      nil ->
        {:noreply, put_flash(socket, :error, "That player is no longer available.")}
    end
  end

  def handle_event("remove_player", %{"id" => id}, socket) do
    selected_players = Enum.reject(socket.assigns.selected_players, &(&1.id == id))

    if socket.assigns.captain && socket.assigns.captain.id == id do
      {:noreply, put_flash(socket, :error, "The captain must remain on the roster.")}
    else
      {:noreply, assign(socket, :selected_players, selected_players)}
    end
  end

  def handle_event("create_team", %{"team" => params}, socket) do
    params =
      params
      |> Map.put("captain_id", socket.assigns.captain && socket.assigns.captain.id)
      |> Map.put("player_ids", Enum.map(socket.assigns.selected_players, & &1.id))

    case Teams.admin_create_team(socket.assigns.current_admin, params) do
      {:ok, team} ->
        {:noreply,
         socket
         |> put_flash(:info, "Team created and roster assigned directly.")
         |> push_navigate(to: ~p"/admin/teams/#{team.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to manage teams.")}

      {:error, reason} when reason in [:invalid_player, :invalid_players, :captain_not_found] ->
        {:noreply, put_flash(socket, :error, "Choose a valid captain and at least one player.")}

      {:error, :player_not_found} ->
        {:noreply,
         put_flash(socket, :error, "One of the selected players is no longer available.")}

      {:error, :already_on_a_team} ->
        {:noreply, put_flash(socket, :error, "Every selected player must be unattached.")}

      {:error, :roster_full} ->
        {:noreply, put_flash(socket, :error, "A team can have no more than 8 players.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :team))}
    end
  end

  defp add_player(players, %Player{} = player) do
    if Enum.any?(players, &(&1.id == player.id)), do: players, else: players ++ [player]
  end

  defp fetch_player(id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id), do: Repo.get(Player, id)
  end
end
