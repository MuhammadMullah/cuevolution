defmodule CuevolutionWeb.Admin.AuditLogLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias CuevolutionWeb.AdminComponents

  @action_types ~w(publish_draw redraw override_group_count record_walkover process_withdrawal deadline_double_walkover verify_result postpone_fixture correct_result correct_points)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audit Log", action_types: @action_types, action_filter: nil)
     |> stream(:audit_logs, Accounts.list_admin_action_logs())}
  end

  def render(assigns) do
    ~H"""
    <AdminComponents.app_shell current_admin={@current_admin} active={:notifications} flash={@flash}>
      <AdminComponents.eyebrow>Governance</AdminComponents.eyebrow>
      <h1 class="mb-5 mt-1 text-3xl font-bold tracking-tight text-ink-950">Audit log</h1>
      <div class="mb-5 flex flex-wrap gap-2 border-b border-ink-200 pb-3">
        <button
          type="button"
          phx-click="filter_action"
          phx-value-action=""
          class={filter_class(@action_filter, nil)}
        >
          All events
        </button>
        <button
          :for={action <- @action_types}
          type="button"
          phx-click="filter_action"
          phx-value-action={action}
          class={filter_class(@action_filter, action)}
        >
          {action_label(action)}
        </button>
      </div>
      <div class="overflow-x-auto rounded-2xl border border-ink-200 bg-white">
        <table class="min-w-full text-left text-sm">
          <thead class="bg-ink-50 font-mono text-[10px] uppercase tracking-wider text-ink-500">
            <tr>
              <th class="px-4 py-3">Actor</th>
              <th class="px-4 py-3">Action</th>
              <th class="px-4 py-3">Entity</th>
              <th class="px-4 py-3">Details</th>
              <th class="px-4 py-3">When</th>
            </tr>
          </thead>
          <tbody id="audit-logs" phx-update="stream" class="divide-y divide-ink-100">
            <tr :for={{id, entry} <- @streams.audit_logs} id={id}>
              <td class="px-4 py-3 font-semibold text-ink-950">{actor_label(entry)}</td>
              <td class="px-4 py-3 text-ink-800">{action_label(entry.action_type)}</td>
              <td class="px-4 py-3 font-mono text-xs text-ink-500">
                {entry.entity_type} · {entry.entity_id}
              </td>
              <td class="max-w-sm px-4 py-3 text-xs text-ink-600">{details(entry)}</td>
              <td class="whitespace-nowrap px-4 py-3 font-mono text-xs text-ink-500">
                {entry.inserted_at}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminComponents.app_shell>
    """
  end

  def handle_event("filter_action", %{"action" => action}, socket) do
    filter = if action == "", do: nil, else: action

    {:noreply,
     socket
     |> assign(:action_filter, filter)
     |> stream(:audit_logs, Accounts.list_admin_action_logs(filter), reset: true)}
  end

  defp actor_label(%{actor_type: "system"}), do: "System"
  defp actor_label(%{admin: %{email: email}}), do: email
  defp actor_label(_), do: "Admin"

  defp details(%{new_value: nil}), do: "—"
  defp details(%{new_value: value}), do: inspect(value)

  defp action_label(action), do: action |> String.replace("_", " ") |> String.capitalize()

  defp filter_class(selected, value) do
    [
      "rounded-full border px-3 py-1.5 text-xs font-semibold capitalize",
      if(selected == value,
        do: "border-red-500 text-ink-950",
        else: "border-transparent text-ink-500 hover:text-ink-950"
      )
    ]
  end
end
