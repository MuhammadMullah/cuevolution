defmodule CuevolutionWeb.Player.MyGroupLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Repo
  alias CuevolutionWeb.{AdminComponents, PlayerComponents}

  def mount(_params, _session, socket) do
    player = socket.assigns.current_player
    group = Competitions.grassroots_group_for_player(player.id)
    rows = if group, do: named_rows(Competitions.grassroots_group_standings(group)), else: []
    current_id = current_participation_id(group, player.id)

    {:ok,
     assign(socket,
       page_title: "My Group",
       group: group,
       rows: rows,
       current_participant_id: current_id
     )}
  end

  def render(assigns) do
    ~H"""
    <PlayerComponents.app_shell
      current_player={@current_player}
      active={:my_group}
      flash={@flash}
      identification_form={@identification_form}
      pending_invitations={@pending_invitations}
    >
      <div class="mx-auto max-w-5xl space-y-6 px-4 py-8">
        <div>
          <p class="font-mono text-xs uppercase tracking-widest text-red-600">Grassroots</p>
          <h1 class="mt-2 text-3xl font-bold text-ink-950">My group</h1>
          <p :if={@group} class="mt-1 text-sm font-semibold text-ink-500">{@group.name}</p>
        </div>
        <div :if={@group}>
          <AdminComponents.grassroots_standings_table
            rows={@rows}
            current_participant_id={@current_participant_id}
          />
          <p class="mt-4 text-sm text-ink-500">
            Points here are frames won plus a clean-sweep bonus — separate from Cuevo Points, which start at Circuit stage.
          </p>
        </div>
        <div :if={!@group} class="rounded-xl border border-ink-200 bg-white p-6 text-ink-500">
          You have not been assigned to a Grassroots group yet.
        </div>
      </div>
    </PlayerComponents.app_shell>
    """
  end

  defp named_rows(rows) do
    ids = Enum.map(rows, & &1.participant_id)

    names =
      Repo.all(from p in StageParticipation, where: p.id in ^ids, preload: :player)
      |> Map.new(&{&1.id, player_name(&1)})

    Enum.map(rows, &Map.put(&1, :name, Map.get(names, &1.participant_id, "Unknown")))
  end

  defp current_participation_id(nil, _player_id), do: nil

  defp current_participation_id(group, player_id) do
    Enum.find_value(group.group_memberships, fn membership ->
      participation = Repo.preload(membership, :stage_participation).stage_participation
      if participation.player_id == player_id, do: participation.id
    end)
  end

  defp player_name(%{player: %{first_name: first, last_name: last}}), do: "#{first} #{last}"
  defp player_name(_), do: "Team"
end
