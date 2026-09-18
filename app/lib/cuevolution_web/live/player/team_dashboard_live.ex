defmodule CuevolutionWeb.TeamDashboardLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team
  alias CuevolutionWeb.PlayerComponents

  @min_roster_size 5

  def mount(_params, _session, socket) do
    if socket.assigns.current_player.team_id do
      {:ok,
       socket
       |> assign(
         page_title: "My Team",
         add_form: to_form(%{}, as: :roster),
         min_roster_size: @min_roster_size
       )
       |> load_team()}
    else
      {:ok, push_navigate(socket, to: ~p"/team/new")}
    end
  end

  def handle_event("add_player", %{"roster" => %{"username" => username}}, socket) do
    if socket.assigns.is_captain do
      {:noreply, socket |> invite_by_username(username) |> load_team()}
    else
      {:noreply, put_flash(socket, :error, "Only the captain can invite players.")}
    end
  end

  def handle_event("remove_player", %{"id" => id}, socket) do
    if socket.assigns.is_captain do
      player = Repo.get!(Player, id)

      socket =
        case Teams.remove_player_from_roster(socket.assigns.team, player) do
          {:ok, _player} ->
            put_flash(socket, :info, "Player removed from the roster.")

          {:error, :roster_frozen} ->
            put_flash(
              socket,
              :error,
              "The roster is frozen, this team has already been drawn into a stage."
            )

          {:error, :not_on_this_team} ->
            put_flash(socket, :error, "That player isn't on this team.")
        end

      {:noreply, load_team(socket)}
    else
      {:noreply, put_flash(socket, :error, "Only the captain can remove players.")}
    end
  end

  def handle_event("cancel_invitation", %{"id" => id}, socket) do
    if socket.assigns.is_captain do
      {:noreply, socket |> cancel_invitation_by_id(id) |> load_team()}
    else
      {:noreply, put_flash(socket, :error, "Only the captain can cancel invitations.")}
    end
  end

  def handle_event("delete_team", _params, socket) do
    if socket.assigns.is_captain do
      case Teams.delete_team(socket.assigns.team, socket.assigns.current_player) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Team deleted.")
           |> push_navigate(to: ~p"/team/new")}

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
    else
      {:noreply, put_flash(socket, :error, "Only the captain can delete the team.")}
    end
  end

  defp invite_by_username(socket, username) do
    case find_player_by_username(username) do
      nil -> put_flash(socket, :error, "No player found with that username.")
      player -> put_invite_flash(socket, Teams.invite_player(socket.assigns.team, player), player)
    end
  end

  defp put_invite_flash(socket, {:ok, _invitation}, player) do
    put_flash(socket, :info, "Invitation sent to @#{player.username}.")
  end

  defp put_invite_flash(socket, {:error, :already_on_a_team}, _player) do
    put_flash(socket, :error, "That player is already on a team.")
  end

  defp put_invite_flash(socket, {:error, :invitation_already_pending}, _player) do
    put_flash(socket, :error, "That player already has a pending invitation.")
  end

  defp put_invite_flash(socket, {:error, :roster_full}, _player) do
    put_flash(socket, :error, "The roster is full (max 8).")
  end

  defp put_invite_flash(socket, {:error, :roster_frozen}, _player) do
    put_flash(
      socket,
      :error,
      "The roster is frozen, this team has already been drawn into a stage."
    )
  end

  defp cancel_invitation_by_id(socket, id) do
    case Teams.get_pending_invitation_for_team_and_id(socket.assigns.team.id, id) do
      nil ->
        put_flash(socket, :error, "That invitation is no longer available.")

      invitation ->
        case Teams.cancel_invitation(invitation, socket.assigns.current_player) do
          {:ok, _invitation} -> put_flash(socket, :info, "Invitation cancelled.")
          {:error, _reason} -> put_flash(socket, :error, "Couldn't cancel that invitation.")
        end
    end
  end

  defp find_player_by_username(username) do
    Repo.one(
      from p in Player, where: fragment("lower(?)", p.username) == ^String.downcase(username)
    )
  end

  defp load_team(socket) do
    player = socket.assigns.current_player
    team = Team |> Repo.get!(player.team_id) |> Repo.preload([:region, :captain, :roster])

    is_captain = team.captain_id == player.id

    assign(socket,
      team: team,
      eligible: Teams.eligible?(team),
      roster_count: length(team.roster),
      is_captain: is_captain,
      sent_invitations:
        if(is_captain, do: Teams.list_pending_invitations_for_team(team.id), else: [])
    )
  end

  defp team_initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end
end
