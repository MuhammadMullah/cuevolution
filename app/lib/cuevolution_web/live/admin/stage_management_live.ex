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
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Competitions.StageCapacityConfig
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  @categories [{"Individual Male", "male"}, {"Individual Female", "female"}, {"Teams", "team"}]
  @group_config_categories ~w(male female team)
  @editable_group_fields ~w(group_size advancer_count target_group_size minimum_group_size minimum_entrants extra_qualifier_count)
  @capped_stages ~w(Circuit Finals)

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
       next_stage: Competitions.next_stage(List.first(stages)),
       region: List.first(regions),
       category: "male",
       panel: :participants,
       editing_config: nil,
       editing_field: nil,
       filter_form:
         to_form(%{"region_id" => List.first(regions).id, "category" => "male"}, as: :filter)
     )
     |> assign_config_form()
     |> assign_deadline_form()
     |> load_participations()
     |> load_configs()
     |> load_group_configs()}
  end

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> assign(:next_stage, Competitions.next_stage(stage))
     |> assign(:editing_field, nil)
     |> assign_deadline_form(stage)
     |> load_participations()
     |> load_configs()
     |> load_group_configs()}
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

  def handle_event("start_edit_field", %{"id" => id, "field" => field}, socket)
      when field in @editable_group_fields do
    {:noreply, assign(socket, :editing_field, {id, field})}
  end

  def handle_event("cancel_edit_field", _params, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end

  def handle_event("save_field", %{"id" => id, "field" => field, "value" => value}, socket)
      when field in @editable_group_fields do
    config = Enum.find(socket.assigns.group_configs, &(&1.id == id))

    socket =
      case config && Competitions.update_group_config(config, %{field => value}) do
        {:ok, _updated} -> load_group_configs(socket)
        _ -> socket
      end

    {:noreply, assign(socket, :editing_field, nil)}
  end

  def handle_event("save_deadline", %{"stage" => %{"completion_deadline" => value}}, socket) do
    parsed = if value == "", do: {:ok, nil}, else: Date.from_iso8601(value)

    case parsed do
      {:ok, deadline} -> save_deadline(socket, deadline)
      _ -> {:noreply, put_flash(socket, :error, "Enter a valid date.")}
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

  # Circuit/Finals are capped stages (knockout brackets) with no group-size
  # formula; Grassroots/Regional always show all three category rows
  # (male/female/team), lazily creating the documented defaults for any
  # category never configured yet — otherwise the settings table would be
  # empty until an admin happened to trigger `get_or_create_group_config/2`
  # indirectly via a draw.
  defp load_group_configs(socket) do
    stage = socket.assigns.stage

    group_configs =
      if stage.name in @capped_stages do
        []
      else
        @group_config_categories
        |> Enum.map(&Competitions.get_or_create_group_config(stage.id, &1))
        |> Enum.sort_by(&Enum.find_index(@group_config_categories, fn c -> c == &1.category end))
      end

    assign(socket, :group_configs, group_configs)
  end

  defp assign_config_form(socket, config \\ nil) do
    changeset = StageCapacityConfig.changeset(config || %StageCapacityConfig{}, %{})
    assign(socket, :config_form, to_form(changeset, as: :config))
  end

  defp assign_deadline_form(socket, stage \\ nil) do
    stage = stage || socket.assigns.stage
    assign(socket, :deadline_form, to_form(Stage.changeset(stage, %{}), as: :stage))
  end

  defp save_deadline(socket, deadline) do
    case Competitions.set_grassroots_deadline(socket.assigns.current_admin, deadline) do
      {:ok, stage} ->
        stages = Enum.map(socket.assigns.stages, &if(&1.id == stage.id, do: stage, else: &1))

        {:noreply,
         socket
         |> assign(stages: stages, stage: stage)
         |> assign_deadline_form(stage)
         |> put_flash(
           :info,
           if(deadline, do: "Grassroots deadline saved.", else: "Grassroots deadline cleared.")
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to set deadlines.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save the deadline.")}
    end
  end

  attr :config, :any, required: true
  attr :field, :string, required: true
  attr :editing_field, :any, required: true

  # Inline click-to-edit cell for a `StageGroupConfig` field, matching the
  # design's dashed-underline-span-becomes-an-input pattern (as opposed to
  # the capacity table's whole-row edit-button form, which is what the
  # design itself uses for that table — the two aren't meant to match).
  defp editable_field(assigns) do
    ~H"""
    <%= if @editing_field == {@config.id, @field} do %>
      <input
        type="number"
        value={Map.fetch!(@config, String.to_existing_atom(@field))}
        autofocus
        phx-blur="save_field"
        phx-keydown="cancel_edit_field"
        phx-key="Escape"
        phx-value-id={@config.id}
        phx-value-field={@field}
        class="w-[70px] rounded-lg border border-red-500 px-2 py-1 font-mono text-sm text-ink-950 focus:outline-none"
      />
    <% else %>
      <span
        phx-click="start_edit_field"
        phx-value-id={@config.id}
        phx-value-field={@field}
        class="cursor-pointer border-b border-dashed border-ink-300 font-mono text-sm text-ink-700"
      >
        {Map.fetch!(@config, String.to_existing_atom(@field))}
      </span>
    <% end %>
    """
  end

  defp group_category_label("male"), do: "Individual Male"
  defp group_category_label("female"), do: "Individual Female"
  defp group_category_label("team"), do: "Teams"

  defp participant_name(%{player_id: nil, team: team}), do: team.name
  defp participant_name(%{player: player}), do: "#{player.first_name} #{player.last_name}"

  defp participant_sub(%{player_id: nil} = p), do: "Team · #{p.region.name}"
  defp participant_sub(p), do: "Player · #{p.region.name}"

  # Matches CuevolutionWeb.PlayerComponents' @stage_styles palette (the
  # actual app design system), not the mockup's latest (incorrect) colors.
  defp stage_tab_active_class("Grassroots"), do: "border-ink-500 bg-ink-100 text-ink-700"
  defp stage_tab_active_class("Regional"), do: "border-green-500 bg-green-100 text-green-700"
  defp stage_tab_active_class(_stage), do: "border-red-500 bg-red-50 text-red-700"
end
