defmodule CuevolutionWeb.HealthController do
  use CuevolutionWeb, :controller

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def startup(conn, _params), do: json(conn, %{status: "ok"})

  def readiness(conn, _params) do
    case Cuevolution.Repo.query("SELECT 1") do
      {:ok, _result} -> json(conn, %{status: "ok"})
      {:error, _reason} -> conn |> put_status(:service_unavailable) |> json(%{status: "error"})
    end
  end
end
