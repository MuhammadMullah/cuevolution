defmodule CuevolutionWeb.GroupManagementLive do
  @moduledoc """
  Admin "Groups" page (spec 006) — Grassroots/Regional stage + region tabs,
  create groups, assign unassigned participants into them. Regional group
  creation auto-creates an empty knockout bracket (FR-004), handled inside
  `Competitions.create_group/1`, not here.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    stages =
      Competitions.list_stages() |> Enum.filter(&(&1.name in ["Grassroots", "Regional"]))

    regions = Accounts.list_regions()

    {:ok,
     socket
     |> assign(
       page_title: "Groups",
       stages: stages,
       regions: regions,
       stage: List.first(stages),
       region: List.first(regions),
       form: to_form(%{}, as: :group)
     )
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("select_region", %{"id" => id}, socket) do
    region = Enum.find(socket.assigns.regions, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:region, region)
     |> load_groups()
     |> load_unassigned()}
  end

  def handle_event("create_group", %{"group" => %{"name" => name}}, socket) do
    attrs = %{stage_id: socket.assigns.stage.id, region_id: socket.assigns.region.id, name: name}

    case Competitions.create_group(attrs) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{group.name}\" created.")
         |> assign(:form, to_form(%{}, as: :group))
         |> load_groups()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :group))}
    end
  end

  def handle_event(
        "assign_to_group",
        %{"group_id" => group_id, "participation_id" => pid},
        socket
      ) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))
    participation = Enum.find(socket.assigns.unassigned, &(&1.id == pid))

    socket =
      case Competitions.assign_to_group(participation, group) do
        {:ok, _membership} ->
          socket
          |> put_flash(:info, "Added to #{group.name}.")
          |> load_groups()
          |> load_unassigned()

        {:error, _changeset} ->
          put_flash(socket, :error, "Couldn't add — already in this group?")
      end

    {:noreply, socket}
  end

  defp load_groups(socket) do
    assign(
      socket,
      :groups,
      Competitions.list_groups(socket.assigns.stage.id, socket.assigns.region.id)
    )
  end

  defp load_unassigned(socket) do
    assign(
      socket,
      :unassigned,
      Competitions.list_unassigned_participations(
        socket.assigns.stage.id,
        socket.assigns.region.id
      )
    )
  end

  defp participant_name(%{player_id: nil, team: team}), do: team.name
  defp participant_name(%{player: player}), do: "#{player.first_name} #{player.last_name}"
end
