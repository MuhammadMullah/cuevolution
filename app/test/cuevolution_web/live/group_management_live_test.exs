defmodule CuevolutionWeb.GroupManagementLiveTest do
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
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/groups")
  end

  test "creating a group for Grassroots does not create a bracket, and lists unassigned participants",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    insert(:stage_participation,
      stage_id: grassroots.id,
      region_id: region.id,
      player_id: player.id
    )

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/groups")

    assert html =~ player.first_name
    refute html =~ "Everyone in this stage/region is already grouped."

    html =
      view
      |> form("form[phx-submit='create_group']", group: %{"name" => "Pool A"})
      |> render_submit()

    assert html =~ "created."
    assert html =~ "Pool A"
  end

  test "assigning an unassigned participant to a group moves them out of the unassigned list",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        player_id: player.id
      )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/groups")

    view
    |> form("form[phx-submit='create_group']", group: %{"name" => "Pool A"})
    |> render_submit()

    html =
      view
      |> form("form[phx-value-group_id]", %{"participation_id" => participation.id})
      |> render_submit()

    assert html =~ "Added to Pool A."
    assert html =~ "Everyone in this stage/region is already grouped."
  end
end
