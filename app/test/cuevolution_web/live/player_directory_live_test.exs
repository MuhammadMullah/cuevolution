defmodule CuevolutionWeb.PlayerDirectoryLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/players")
  end

  test "lists players and filters by region", %{conn: conn} do
    region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
    region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

    player_a = insert(:player, region_id: region_a.id, username: "regionaplayer")
    player_b = insert(:player, region_id: region_b.id, username: "regionbplayer")

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/players")

    assert html =~ player_a.username
    assert html =~ player_b.username

    html =
      view
      |> form("#player-filter-form", filter: %{"region_id" => region_a.id})
      |> render_change()

    assert html =~ player_a.username
    refute html =~ player_b.username
  end

  test "lists teams alongside players, and the Kind filter isolates each", %{conn: conn} do
    player = insert(:player, username: "soloplayer")
    team = insert(:team, name: "Westlands Cue Kings")

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/players")

    assert html =~ player.username
    assert html =~ team.name

    html =
      view
      |> form("#player-filter-form", filter: %{"kind" => "team"})
      |> render_change()

    assert html =~ team.name
    refute html =~ player.username

    html =
      view
      |> form("#player-filter-form", filter: %{"kind" => "male"})
      |> render_change()

    refute html =~ team.name
  end

  test "clicking a team row navigates to the team detail page", %{conn: conn} do
    team = insert(:team, name: "Rift Valley Racks")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/players")

    {:ok, _detail_view, html} =
      view
      |> element("a", team.name)
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ team.name
  end
end
