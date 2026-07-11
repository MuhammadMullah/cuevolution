defmodule CuevolutionWeb.FixturesLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts

  defp log_in_player(conn, player) do
    token = Accounts.generate_player_session_token(player)
    conn |> init_test_session(%{}) |> put_session(:player_token, token)
  end

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/fixtures")
  end

  test "shows the no-upcoming-fixtures empty state — no Competitions data exists yet", %{
    conn: conn
  } do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "My fixtures"
    assert html =~ "No upcoming fixtures"
    refute html =~ "A new draw has been published"
  end

  test "shows the no-results-yet empty state — no Competitions data exists yet", %{conn: conn} do
    player = insert(:player)
    conn = log_in_player(conn, player)

    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "Recent results"
    assert html =~ "No matches played yet"
  end

  test "shows the same empty states for a player with a team", %{conn: conn} do
    captain = insert(:player)
    {:ok, _team} = Cuevolution.Teams.create_team(captain, %{"name" => "The Sharks"})
    captain = Cuevolution.Repo.get!(Cuevolution.Accounts.Player, captain.id)

    conn = log_in_player(conn, captain)
    {:ok, _view, html} = live(conn, ~p"/fixtures")

    assert html =~ "No upcoming fixtures"
    assert html =~ "No matches played yet"
  end
end
