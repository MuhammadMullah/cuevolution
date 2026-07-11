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
    case find_player_by_username(username) do
      nil ->
        {:noreply, put_flash(socket, :error, "No player found with that username.")}

      player ->
        socket =
          case Teams.add_player_to_roster(socket.assigns.team, player) do
            {:ok, _player} ->
              put_flash(socket, :info, "Player added to the roster.")

            {:error, :already_on_a_team} ->
              put_flash(socket, :error, "That player is already on a team.")

            {:error, :roster_full} ->
              put_flash(socket, :error, "The roster is full (max 8).")
          end

        {:noreply, load_team(socket)}
    end
  end

  def handle_event("remove_player", %{"id" => id}, socket) do
    player = Repo.get!(Player, id)
    {:ok, _player} = Teams.remove_player_from_roster(socket.assigns.team, player)

    {:noreply,
     socket
     |> put_flash(:info, "Player removed from the roster.")
     |> load_team()}
  end

  defp find_player_by_username(username) do
    Repo.one(
      from p in Player, where: fragment("lower(?)", p.username) == ^String.downcase(username)
    )
  end

  defp load_team(socket) do
    player = socket.assigns.current_player
    team = Team |> Repo.get!(player.team_id) |> Repo.preload([:region, :captain, :roster])

    assign(socket,
      team: team,
      eligible: Teams.eligible?(team),
      roster_count: length(team.roster),
      is_captain: team.captain_id == player.id
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
