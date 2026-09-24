defmodule CuevolutionWeb.Player.MyGroupLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Stage

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/my-group")
  end

  test "derives the group from the authenticated player, ignoring a crafted group parameter", %{
    conn: conn
  } do
    grassroots = Cuevolution.Repo.get_by!(Stage, name: "Grassroots")
    region = build(:region)
    player = insert(:player, region_id: region.id, gender: "male", first_name: "Mine")
    other = insert(:player, region_id: region.id, gender: "male", first_name: "Other")
    venue = insert(:venue, region_id: region.id)

    {:ok, mine_group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Mine Group"
      })

    {:ok, other_group} =
      Competitions.create_group(%{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: "Other Group"
      })

    mine_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    other_participation =
      insert(:stage_participation,
        stage_id: grassroots.id,
        region_id: region.id,
        category: "male",
        player_id: other.id
      )

    {:ok, _} = Competitions.assign_to_group(mine_participation, mine_group)
    {:ok, _} = Competitions.assign_to_group(other_participation, other_group)

    conn = log_in_player(conn, player)
    {:ok, _view, html} = live(conn, ~p"/my-group?group_id=#{other_group.id}")

    assert html =~ "Mine Group"
    refute html =~ "Other Group"
    assert html =~ "YOU"
  end
end
