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

  test "loads the region filter from the query string", %{conn: conn} do
    region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
    region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

    player_a = insert(:player, region_id: region_a.id, username: "queryregionplayer")
    player_b = insert(:player, region_id: region_b.id, username: "otherqueryplayer")

    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/players?region_id=#{region_a.id}")

    assert html =~ player_a.username
    refute html =~ player_b.username
    assert html =~ ~s(name="filter[region_id]")
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

  test "filters by stage without loading every participation in the system", %{conn: conn} do
    grassroots = Cuevolution.Repo.get_by!(Cuevolution.Competitions.Stage, name: "Grassroots")
    regional = Cuevolution.Repo.get_by!(Cuevolution.Competitions.Stage, name: "Regional")

    player_in_grassroots = insert(:player, username: "grassrootsplayer")
    player_in_regional = insert(:player, username: "regionalplayer")

    insert(:stage_participation, player_id: player_in_grassroots.id, stage_id: grassroots.id)
    insert(:stage_participation, player_id: player_in_regional.id, stage_id: regional.id)

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/players")

    html =
      view
      |> form("#player-filter-form", filter: %{"stage_id" => grassroots.id})
      |> render_change()

    assert html =~ player_in_grassroots.username
    refute html =~ player_in_regional.username
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

  test "paginates large result sets", %{conn: conn} do
    insert_list(51, :player)

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/players")

    assert html =~ "Showing 50 of 51 results"
    assert has_element?(view, "#directory-next-page")

    html = view |> element("#directory-next-page") |> render_click()

    assert html =~ "Showing 1 of 51 results"
    assert has_element?(view, "#directory-previous-page")
  end

  # Players and teams are two queries behind one paginated list. They each
  # used to get the whole page window, so page 1 ran to twice the page size
  # and the pager — sized on the combined count — trailed empty pages.
  # (`:team` inserts a captain, so the totals are read back rather than
  # assumed.)
  defp directory_total do
    Cuevolution.Repo.aggregate(Cuevolution.Accounts.Player, :count, :id) +
      Cuevolution.Repo.aggregate(Cuevolution.Teams.Team, :count, :id)
  end

  test "a page of mixed players and teams holds one page worth of rows", %{conn: conn} do
    insert_list(40, :player)
    insert_list(15, :team)

    total = directory_total()
    assert total > 50, "needs to spill past one page to be a pagination test"

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/players")

    assert html =~ "Showing 50 of #{total} results"

    html = view |> element("#directory-next-page") |> render_click()

    assert html =~ "Showing #{total - 50} of #{total} results"
    refute html =~ "No matches for these filters"
  end

  test "every player and team is reachable across the pages, exactly once", %{conn: conn} do
    # Trailing marker so no name is a prefix of another ("pager1z" would
    # otherwise match inside "pager10z" and look present on both pages).
    players = for i <- 1..45, do: insert(:player, username: "dirpager#{i}z")
    teams = for i <- 1..10, do: insert(:team, name: "DirPagerTeam#{i}z")

    total = directory_total()

    conn = log_in_admin(conn)
    {:ok, view, page_one} = live(conn, ~p"/admin/players")
    page_two = view |> element("#directory-next-page") |> render_click()

    assert page_one =~ "Showing 50 of #{total} results"
    assert page_two =~ "Showing #{total - 50} of #{total} results"

    for row <- Enum.map(players, & &1.username) ++ Enum.map(teams, & &1.name) do
      assert page_one =~ row != (page_two =~ row),
             "expected #{row} on exactly one of the two pages"
    end
  end

  describe "search" do
    # The directory lists players by name but stores a separate handle, so
    # every one of these was a player sitting in the table that the page
    # swore did not exist.
    test "finds a player by name, not just by username", %{conn: conn} do
      player = insert(:player, first_name: "Martin", last_name: "Mwangi", username: "Lesta")
      other = insert(:player, first_name: "Jeff", last_name: "Kibet", username: "Blackmamba")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      for term <- ["Martin", "Mwangi", "Martin Mwangi", "Mwangi Martin", "martin mwangi"] do
        html = view |> form("#player-filter-form", filter: %{"search" => term}) |> render_change()

        assert html =~ player.username, "expected #{term} to find @#{player.username}"
        refute html =~ other.username
      end
    end

    test "finds a player typed with the @ the page prints before a username", %{conn: conn} do
      player = insert(:player, username: "MAS", first_name: "Mohamed", last_name: "Said")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      for term <- ["MAS", "@MAS", "mas", "@mas"] do
        html = view |> form("#player-filter-form", filter: %{"search" => term}) |> render_change()
        assert html =~ player.first_name, "expected #{term} to find @#{player.username}"
      end
    end

    # A handle may contain `@` itself, so the term as typed has to keep
    # working — stripping cannot be unconditional.
    test "finds usernames that themselves contain @", %{conn: conn} do
      bk = insert(:player, username: "Bk@123", first_name: "Brian", last_name: "Kimani")
      vans = insert(:player, username: "@Vans01", first_name: "Vanessa", last_name: "Otieno")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      for {term, expected} <- [
            {"Bk@123", bk},
            {"BK@123", bk},
            {"@Bk@123", bk},
            {"@Vans01", vans},
            {"Vans01", vans},
            {"@@Vans01", vans},
            {"@VANS01", vans}
          ] do
        html = view |> form("#player-filter-form", filter: %{"search" => term}) |> render_change()
        assert html =~ expected.first_name, "expected #{term} to find @#{expected.username}"
      end
    end

    test "tolerates whitespace from a pasted term", %{conn: conn} do
      player = insert(:player, first_name: "Amos", last_name: "Netima", username: "Netima47ak")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      for term <- ["  Netima47ak  ", " @Netima47ak ", "Amos   Netima"] do
        html = view |> form("#player-filter-form", filter: %{"search" => term}) |> render_change()
        assert html =~ player.username, "expected #{inspect(term)} to find the player"
      end
    end

    test "matches teams by name under the same term", %{conn: conn} do
      team = insert(:team, name: "Nairobi Cue Kings")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      html =
        view
        |> form("#player-filter-form", filter: %{"search" => " cue kings "})
        |> render_change()

      assert html =~ team.name
    end

    test "a blank term does not filter anything out", %{conn: conn} do
      player = insert(:player, username: "stillhere")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      html = view |> form("#player-filter-form", filter: %{"search" => "   "}) |> render_change()

      assert html =~ player.username
    end

    # The count used to ignore `search`/`kind` entirely, so a search that
    # matched nothing still advertised every player in the system — which
    # read as a broken list rather than a bad term.
    test "the reported total agrees with the rows actually shown", %{conn: conn} do
      insert(:player, first_name: "Faith", last_name: "Wambui", username: "faithw")
      insert_list(3, :player)

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      html =
        view |> form("#player-filter-form", filter: %{"search" => "Faith"}) |> render_change()

      assert html =~ "Showing 1 of 1 result"

      html =
        view
        |> form("#player-filter-form", filter: %{"search" => "zzznomatch"})
        |> render_change()

      assert html =~ "Showing 0 of 0 results"
      assert html =~ "No matches for these filters"
    end

    test "the reported total honours the Kind filter", %{conn: conn} do
      insert_list(2, :player, gender: "female")
      insert_list(3, :player, gender: "male")

      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/players")

      html = view |> form("#player-filter-form", filter: %{"kind" => "female"}) |> render_change()

      assert html =~ "Showing 2 of 2 results"
    end
  end

  test "filters players and teams by venue", %{conn: conn} do
    venue_a = insert(:venue)
    venue_b = insert(:venue)

    player_a = insert(:player, preferred_venue_id: venue_a.id, username: "venueaplayer")
    player_b = insert(:player, preferred_venue_id: venue_b.id, username: "venuebplayer")

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/players")

    html =
      view
      |> form("#player-filter-form", filter: %{"venue_id" => venue_a.id})
      |> render_change()

    assert html =~ player_a.username
    refute html =~ player_b.username
  end

  test "export buttons submit the live filter form directly, instead of a computed link", %{
    conn: conn
  } do
    conn = log_in_admin(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/players")

    # Deliberately not a `href="...?region_id=..."` computed from the
    # LiveView's last-patched assigns (see AdminDirectoryExportController's
    # moduledoc): that lags a step behind whatever's actually selected in
    # the form until the next phx-change round-trip lands, so two quick,
    # different filter picks could both export the same, stale result.
    # Native `formaction`/`form` submission always uses the form's current,
    # in-DOM values with no server round-trip involved.
    assert html =~ ~s(formaction="/admin/directory/export.csv")
    assert html =~ ~s(formaction="/admin/directory/export.xlsx")
    assert html =~ ~s(form="player-filter-form")
    assert html =~ ~s(formmethod="get")
  end
end
