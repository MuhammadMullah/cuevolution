defmodule CuevolutionWeb.TeamCreationLive do
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    if socket.assigns.current_player.team_id do
      {:ok, push_navigate(socket, to: ~p"/team")}
    else
      {:ok, assign(socket, page_title: "Create a Team")}
    end
  end
end
