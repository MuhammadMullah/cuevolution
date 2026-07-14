defmodule CuevolutionWeb.TeamDetailLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Repo
  alias Cuevolution.Teams
  alias Cuevolution.Teams.Team
  alias CuevolutionWeb.AdminComponents
  alias CuevolutionWeb.PlayerComponents

  def mount(%{"id" => id}, _session, socket) do
    team = Team |> Repo.get!(id) |> Repo.preload([:region, :captain, roster: []])

    {:ok,
     assign(socket,
       page_title: "Team Detail",
       team: team,
       eligible: Teams.eligible?(team)
     )}
  end
end
