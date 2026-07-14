defmodule CuevolutionWeb.AdminResultsLive do
  @moduledoc """
  Admin "Results & Points" page — reproduces the chrome (Unplayed / Played
  tabs) of `project-scope/Quevolution/Cuevolution Admin.dc.html`'s Results
  screen, but with no backing data: `Cuevolution.Competitions`
  (draws/match results) doesn't exist yet, same deferral as `AdminDrawsLive`
  and the player-facing `FixturesLive`/`StandingsLive`. The fixture list is
  therefore always empty.
  """
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Results & Points", tab: "unplayed")}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end
end
