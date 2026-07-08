defmodule CuevolutionWeb.PageController do
  use CuevolutionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
