defmodule CuevolutionWeb.AdminDashboardLive do
  use CuevolutionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin Dashboard")}
  end
end
