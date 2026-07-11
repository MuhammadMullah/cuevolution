defmodule CuevolutionWeb.PlayerDetailLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Repo

  def mount(%{"id" => id}, _session, socket) do
    player = Player |> Repo.get!(id) |> Repo.preload(:region)
    {:ok, assign(socket, page_title: "Player Detail", player: player)}
  end
end
