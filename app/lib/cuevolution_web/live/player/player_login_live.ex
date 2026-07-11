defmodule CuevolutionWeb.PlayerLoginLive do
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :player), page_title: "Sign In")}
  end
end
