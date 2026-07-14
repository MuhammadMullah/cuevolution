defmodule CuevolutionWeb.StageManagementLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/stages")
  end

  test "shows all 4 stages and lists participants for the selected one", %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    insert(:stage_participation,
      stage_id: grassroots.id,
      region_id: region.id,
      category: "male",
      player_id: player.id
    )

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/stages")

    assert html =~ "Grassroots"
    assert html =~ "Regional"
    assert html =~ "Circuit"
    assert html =~ "Finals"
    assert html =~ player.first_name
  end

  test "advancing a participant moves them to the next stage", %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    html =
      view
      |> element("button[phx-value-id='#{participation.id}']", "Advance")
      |> render_click()

    assert html =~ "Advanced to Regional"
    refute html =~ player.first_name
  end

  test "switching to the capacity panel shows the stage's configured limits", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    circuit_button = view |> element("button", "Circuit")
    html = render_click(circuit_button)
    assert html =~ "Circuit"

    html = view |> element("button", "Capacity") |> render_click()
    assert html =~ "male"
    assert html =~ "128"
  end
end
