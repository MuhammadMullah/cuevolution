defmodule CuevolutionWeb.NotificationLogLive do
  @moduledoc """
  Admin-visible notification delivery log (spec 002 User Story 3) — lets an
  admin check whether a given notification actually reached the player
  (sent), is still in flight (pending/sending), or failed (with the error
  detail and retry count), without needing DB access.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias CuevolutionWeb.AdminComponents

  @statuses ~w(pending sending sent failed)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Notification Log",
       statuses: @statuses,
       status_filter: nil
     )
     |> stream(:notifications, list_notifications(nil))}
  end

  def handle_event("filter_status", %{"id" => status}, socket) do
    status = if status == "", do: nil, else: status

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> stream(:notifications, list_notifications(status), reset: true)}
  end

  defp list_notifications(status) do
    Notification
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> limit(200)
    |> preload(:player)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  @doc false
  def status_badge_class("sent"), do: "bg-[#DCF3E4] text-[#0E6A30]"
  def status_badge_class("failed"), do: "bg-red-50 text-red-700"
  def status_badge_class(_pending_or_sending), do: "bg-ink-100 text-ink-700"
end
