defmodule CuevolutionWeb.HealthControllerTest do
  use CuevolutionWeb.ConnCase

  test "liveness endpoint returns ok", %{conn: conn} do
    conn = get(conn, "/health/live")

    assert response(conn, 200) == ~s({"status":"ok"})
  end

  test "startup endpoint returns ok", %{conn: conn} do
    conn = get(conn, "/health/startup")

    assert response(conn, 200) == ~s({"status":"ok"})
  end

  test "readiness endpoint returns ok when the database is available", %{conn: conn} do
    conn = get(conn, "/health/readiness")

    assert response(conn, 200) == ~s({"status":"ok"})
  end
end
