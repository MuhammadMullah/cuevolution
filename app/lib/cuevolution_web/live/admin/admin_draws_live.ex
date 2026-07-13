defmodule CuevolutionWeb.AdminDrawsLive do
  @moduledoc """
  Admin "Draws" (fixture entry) page — reproduces the chrome and row-editing
  interaction of `project-scope/Quevolution/Cuevolution Admin.dc.html`'s
  Draws screen, but with no backing data: `Cuevolution.Competitions`
  (rounds/draws/match results) doesn't exist yet — same deferral already
  called out in the player-facing `FixturesLive`/`StandingsLive`. Rows here
  are a client-visible scratchpad only; "Save round & notify players"
  doesn't persist or notify anyone until that context exists.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  @categories [{"Individual Male", "male"}, {"Individual Female", "female"}, {"Teams", "team"}]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Draws", venues: Venues.list_venues(%{}), categories: @categories)
     |> assign(:next_id, 1)
     |> assign(:rows, [blank_row(0)])}
  end

  def handle_event("add_row", _params, socket) do
    id = socket.assigns.next_id

    {:noreply,
     socket
     |> update(:rows, &(&1 ++ [blank_row(id)]))
     |> assign(:next_id, id + 1)}
  end

  def handle_event("remove_row", %{"id" => id}, socket) do
    id = String.to_integer(id)
    remaining = Enum.reject(socket.assigns.rows, &(&1.id == id))

    case remaining do
      [] ->
        new_id = socket.assigns.next_id
        {:noreply, socket |> assign(:rows, [blank_row(new_id)]) |> assign(:next_id, new_id + 1)}

      rows ->
        {:noreply, assign(socket, :rows, rows)}
    end
  end

  def handle_event("update_rows", %{"rows" => rows_params}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case rows_params[Integer.to_string(row.id)] do
          nil ->
            row

          params ->
            %{
              row
              | category: params["category"] || row.category,
                a: params["a"] || "",
                b: params["b"] || "",
                venue_id: blank_to_nil(params["venue_id"]),
                date: params["date"] || "",
                time: params["time"] || ""
            }
        end
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("save", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       "Draws entry isn't connected to a scheduling system yet — nothing was saved or sent."
     )}
  end

  defp blank_row(id),
    do: %{id: id, category: "male", a: "", b: "", venue_id: nil, date: "", time: ""}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
