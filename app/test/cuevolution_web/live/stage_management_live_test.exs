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

  test "the Grassroots deadline box shows on both panels, not just Group settings", %{
    conn: conn
  } do
    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/stages")

    assert html =~ "Grassroots deadline:"

    html = view |> element("button", "Group settings") |> render_click()
    assert html =~ "Grassroots deadline:"
  end

  test "Grassroots Group settings shows the formula columns and best-of-rest table", %{
    conn: conn
  } do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    html = view |> element("button", "Group settings") |> render_click()

    assert html =~ "Target size"
    assert html =~ "Min size"
    assert html =~ "Min entrants"
    assert html =~ "Best-of-rest qualifiers"
    assert html =~ "Individual Male"
    assert html =~ "Individual Female"
    assert html =~ "Teams"
  end

  test "Regional Group settings has no formula columns or best-of-rest table", %{conn: conn} do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    view |> element("button", "Regional") |> render_click()
    html = view |> element("button", "Group settings") |> render_click()

    refute html =~ "Target size"
    refute html =~ "Best-of-rest qualifiers"
    assert html =~ "Group size"
  end

  test "clicking a group-size value opens an inline editor that saves on blur", %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    config = Cuevolution.Competitions.get_or_create_group_config(grassroots.id, "male")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")
    view |> element("button", "Group settings") |> render_click()

    html =
      view
      |> element("span[phx-value-id='#{config.id}'][phx-value-field='group_size']")
      |> render_click()

    assert html =~ ~s(phx-value-field="group_size")
    assert html =~ "<input"

    html =
      view
      |> element("input[phx-value-id='#{config.id}'][phx-value-field='group_size']")
      |> render_blur(%{value: "10"})

    refute html =~ ~s(<input type="number" value="10")

    updated = Cuevolution.Competitions.group_config(grassroots.id, "male")
    assert updated.group_size == 10
  end
end
