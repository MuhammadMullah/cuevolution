defmodule CuevolutionWeb.AdminLoginLive do
  use CuevolutionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :admin), page_title: "Admin Login")}
  end
end
