defmodule CuevolutionWeb.PlayerDirectoryLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo

  def mount(_params, _session, socket) do
    regions = Repo.all(from r in Region, order_by: r.name)

    {:ok,
     socket
     |> assign(
       page_title: "Player Directory",
       regions: regions,
       filter_form: to_form(%{}, as: :filter)
     )
     |> stream(:players, Accounts.list_players_filtered(%{}))}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    filters = build_filters(params)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(params, as: :filter))
     |> stream(:players, Accounts.list_players_filtered(filters), reset: true)}
  end

  defp build_filters(params) do
    %{}
    |> maybe_put_filter(:region_id, blank_to_nil(params["region_id"]))
    |> maybe_put_filter(:category, blank_to_nil(params["category"]))
    |> maybe_put_filter(:username, blank_to_nil(params["username"]))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put_filter(filters, _key, nil), do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)
end
