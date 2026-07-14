defmodule CuevolutionWeb.StageManagementLive do
  @moduledoc """
  Admin "Stages" page (spec 006) — advance individual/team participations
  through the pipeline (Grassroots → Regional → Circuit → Finals), and edit
  Circuit/Finals capacity limits. Two panels on one route: `:participants`
  (default) and `:capacity`, toggled via `push_patch` rather than a second
  full mount, since capacity editing is a small settings form.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.StageCapacityConfig
  alias CuevolutionWeb.AdminComponents

  @categories [{"Individual Male", "male"}, {"Individual Female", "female"}, {"Teams", "team"}]

  def mount(_params, _session, socket) do
    stages = Competitions.list_stages()
    regions = Accounts.list_regions()

    {:ok,
     socket
     |> assign(
       page_title: "Stages",
       stages: stages,
       regions: regions,
       categories: @categories,
       stage: List.first(stages),
       region: List.first(regions),
       category: "male",
       panel: :participants,
       editing_config: nil,
       filter_form:
         to_form(%{"region_id" => List.first(regions).id, "category" => "male"}, as: :filter)
     )
     |> assign_config_form()
     |> load_participations()
     |> load_configs()}
  end

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> load_participations()
     |> load_configs()}
  end

  def handle_event("filter_participants", %{"filter" => params}, socket) do
    region = Enum.find(socket.assigns.regions, &(&1.id == params["region_id"]))

    {:noreply,
     socket
     |> assign(:region, region)
     |> assign(:category, params["category"])
     |> assign(:filter_form, to_form(params, as: :filter))
     |> load_participations()}
  end

  def handle_event("switch_panel", %{"panel" => panel}, socket) do
    {:noreply, assign(socket, :panel, String.to_existing_atom(panel))}
  end

  def handle_event("advance", %{"id" => participation_id}, socket) do
    participation = Enum.find(socket.assigns.participations, &(&1.id == participation_id))
    target = Competitions.next_stage(socket.assigns.stage)

    socket =
      case target && Competitions.advance_to_stage(participation, target) do
        nil ->
          put_flash(socket, :error, "There is no stage after Finals.")

        {:ok, _participation} ->
          put_flash(socket, :info, "Advanced to #{target.name}.")

        {:error, :capacity_exceeded} ->
          put_flash(socket, :error, "#{target.name} is at capacity for this category.")

        {:error, _changeset} ->
          put_flash(socket, :error, "Couldn't advance — please try again.")
      end

    {:noreply, load_participations(socket)}
  end

  def handle_event("edit_config", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.configs, &(&1.id == id))
    {:noreply, socket |> assign(:editing_config, config) |> assign_config_form(config)}
  end

  def handle_event("cancel_edit_config", _params, socket) do
    {:noreply, socket |> assign(:editing_config, nil) |> assign_config_form()}
  end

  def handle_event("save_config", %{"config" => params}, socket) do
    case Competitions.update_capacity_config(socket.assigns.editing_config, params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Capacity for #{config.category} updated to #{config.capacity_limit}."
         )
         |> assign(:editing_config, nil)
         |> assign_config_form()
         |> load_configs()}

      {:error, changeset} ->
        {:noreply, assign(socket, :config_form, to_form(changeset, as: :config))}
    end
  end

  defp load_participations(socket) do
    assign(
      socket,
      :participations,
      Competitions.list_participations(%{
        stage_id: socket.assigns.stage.id,
        region_id: socket.assigns.region.id,
        category: socket.assigns.category
      })
    )
  end

  defp load_configs(socket) do
    assign(socket, :configs, Competitions.list_capacity_configs(socket.assigns.stage.id))
  end

  defp assign_config_form(socket, config \\ nil) do
    changeset = StageCapacityConfig.changeset(config || %StageCapacityConfig{}, %{})
    assign(socket, :config_form, to_form(changeset, as: :config))
  end

  defp participant_name(%{player_id: nil, team: team}), do: team.name
  defp participant_name(%{player: player}), do: "#{player.first_name} #{player.last_name}"
end
