defmodule CuevolutionWeb.AdminLoginLive do
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :admin), page_title: "Admin sign in")}
  end
end
