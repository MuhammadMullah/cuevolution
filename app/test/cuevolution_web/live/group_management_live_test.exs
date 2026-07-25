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

  test "creating a group for Grassroots requires the auto-selected venue and never creates a bracket",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    venue = insert(:venue, region_id: region.id)
    player = insert(:player, region_id: region.id, gender: "male")

    insert(:stage_participation,
      stage_id: grassroots.id,
      region_id: region.id,
      category: "male",
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

    group = Repo.get_by!(Cuevolution.Competitions.Group, name: "Pool A")
    assert group.venue_id == venue.id
    refute Repo.get_by(Cuevolution.Competitions.KnockoutBracket, stage_id: grassroots.id)
  end

  test "assigning an unassigned participant to a group moves them out of the unassigned list",
       %{conn: conn} do
    grassroots = Repo.get_by!(Stage, name: "Grassroots")
    region = List.first(Accounts.list_regions())
    insert(:venue, region_id: region.id)
    player = insert(:player, region_id: region.id, gender: "male")

    participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/groups")

    view
    |> form("form[phx-submit='create_group']", group: %{"name" => "Pool A"})
    |> render_submit()

    group = Repo.get_by!(Cuevolution.Competitions.Group, name: "Pool A")

    # Group cards are collapsed by default — expand it to reach the
    # "+ Add member…" form inside.
    view |> element("button[phx-value-id='#{group.id}']") |> render_click()

    html =
      view
      |> form("form[phx-value-group_id]", %{"participation_id" => participation.id})
      |> render_change()

    assert html =~ "Added to Pool A."
    assert html =~ "Everyone in this stage/region is already grouped."
  end
end
