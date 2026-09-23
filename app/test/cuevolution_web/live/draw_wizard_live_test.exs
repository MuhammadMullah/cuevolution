defmodule CuevolutionWeb.DrawWizardLiveTest do
  use CuevolutionWeb.ConnCase, async: false

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
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/draws/new")
  end

  test "proposes a Grassroots draw for a selected venue and category", %{conn: conn} do
    stage = Repo.get_by!(Stage, name: "Grassroots")
    venue = insert(:venue)

    for _ <- 1..8 do
      player = insert(:player, region_id: venue.region_id, preferred_venue_id: venue.id)

      insert(:stage_participation,
        stage_id: stage.id,
        region_id: venue.region_id,
        category: "male",
        player_id: player.id,
        team_id: nil
      )
    end

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/draws/new")

    assert html =~ "Run a draw"

    html =
      view
      |> form("#draw-wizard-form",
        draw: %{stage_id: stage.id, venue_id: venue.id, category: "male"}
      )
      |> render_submit()

    assert html =~ "Formula preview"
    assert html =~ "8 entrants → 1 groups"
  end
end
