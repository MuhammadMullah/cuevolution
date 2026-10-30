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

  test "shows all 5 stages and lists participants for the selected one", %{conn: conn} do
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
    assert html =~ "Grassroots Round 2"
    assert html =~ "Regional"
    assert html =~ "Circuit"
    assert html =~ "Finals"
    assert html =~ player.first_name
  end

  # A participation carries its own region/category snapshot taken at
  # enrollment. When one drifts from the player's profile, these filters are
  # the only way the row stays reachable at all.
  describe "All regions / All categories filters" do
    setup %{conn: conn} do
      grassroots = Repo.get_by!(Stage, name: "Grassroots")
      [region_a, region_b | _] = Accounts.list_regions()

      here = insert(:player, region_id: region_a.id, gender: "male", last_name: "Inregion")
      elsewhere = insert(:player, region_id: region_b.id, gender: "male", last_name: "Offregion")
      female = insert(:player, region_id: region_a.id, gender: "female", last_name: "Othercat")

      for {player, region, category} <- [
            {here, region_a, "male"},
            {elsewhere, region_b, "male"},
            {female, region_a, "female"}
          ] do
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: category,
          player_id: player.id
        )
      end

      {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin/stages")

      %{view: view, here: here, elsewhere: elsewhere, female: female, region_a: region_a}
    end

    defp filter(view, params) do
      view |> form("#participant-filter-form", filter: params) |> render_change()
    end

    test "default view is still scoped to one region and category", %{
      view: view,
      here: here,
      elsewhere: elsewhere,
      female: female,
      region_a: region_a
    } do
      html = filter(view, %{"region_id" => region_a.id, "category" => "male"})

      assert html =~ here.last_name
      refute html =~ elsewhere.last_name
      refute html =~ female.last_name
    end

    test "clearing the region shows participants from every region", %{
      view: view,
      here: here,
      elsewhere: elsewhere
    } do
      html = filter(view, %{"region_id" => "", "category" => "male"})

      assert html =~ here.last_name
      assert html =~ elsewhere.last_name
    end

    test "clearing the category shows every category", %{
      view: view,
      here: here,
      female: female,
      region_a: region_a
    } do
      html = filter(view, %{"region_id" => region_a.id, "category" => ""})

      assert html =~ here.last_name
      assert html =~ female.last_name
    end

    test "clearing both reaches a participation stranded on either axis", %{
      view: view,
      here: here,
      elsewhere: elsewhere,
      female: female
    } do
      html = filter(view, %{"region_id" => "", "category" => ""})

      assert html =~ here.last_name
      assert html =~ elsewhere.last_name
      assert html =~ female.last_name
    end
  end

  describe "participant search" do
    setup %{conn: conn} do
      grassroots = Repo.get_by!(Stage, name: "Grassroots")
      region = List.first(Accounts.list_regions())

      player =
        insert(:player,
          region_id: region.id,
          gender: "male",
          first_name: "Mohamed",
          last_name: "Said",
          username: "MAS"
        )

      other =
        insert(:player,
          region_id: region.id,
          gender: "male",
          first_name: "Vanessa",
          last_name: "Otieno",
          username: "@Vans01"
        )

      for p <- [player, other] do
        insert(:stage_participation,
          stage_id: grassroots.id,
          region_id: region.id,
          category: "male",
          player_id: p.id
        )
      end

      {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin/stages")

      %{view: view, player: player, other: other}
    end

    defp search(view, term) do
      view |> form("#participant-search-form", search: %{"term" => term}) |> render_change()
    end

    test "matches on name as well as username", %{view: view, player: player, other: other} do
      for term <- ["Mohamed", "Said", "Mohamed Said", "Said Mohamed", "mohamed said"] do
        html = search(view, term)
        assert html =~ player.last_name, "expected #{term} to match"
        refute html =~ other.last_name
      end
    end

    test "matches a username typed with the @ prefix the UI shows", %{view: view, player: player} do
      for term <- ["MAS", "@MAS", "mas", " @MAS "] do
        assert search(view, term) =~ player.last_name, "expected #{inspect(term)} to match"
      end
    end

    test "matches a username that itself contains @", %{view: view, other: other} do
      for term <- ["@Vans01", "Vans01", "@@Vans01", "@VANS01"] do
        assert search(view, term) =~ other.last_name, "expected #{term} to match"
      end
    end

    test "a blank term clears the filter rather than hiding everyone", %{
      view: view,
      player: player,
      other: other
    } do
      refute search(view, "Mohamed") =~ other.last_name

      html = search(view, "   ")

      assert html =~ player.last_name
      assert html =~ other.last_name
    end
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

    assert html =~ "Advanced to Grassroots Round 2"
    refute html =~ player.first_name
  end

  test "Grassroots Round 2 deadline box and formula columns work the same as Grassroots", %{
    conn: conn
  } do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    html = view |> element("button", "Grassroots Round 2") |> render_click()
    assert html =~ "Grassroots Round 2 deadline:"

    html = view |> element("button", "Group settings") |> render_click()
    assert html =~ "Target size"
    assert html =~ "Min size"
    assert html =~ "Min entrants"
    assert html =~ "Best-of-rest qualifiers"
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
    regional = Repo.get_by!(Stage, name: "Regional")
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    # Exact-id select, not a text match — "Regional" is now also a
    # substring of the "Regional Round 2" tab's button text.
    view |> element("button[phx-value-id='#{regional.id}']") |> render_click()
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

  test "moving a participant back returns them to the previous stage", %{conn: conn} do
    regional = Repo.get_by!(Stage, name: "Regional")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    participation =
      insert(:stage_participation,
        stage_id: regional.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    view
    |> element("button[phx-click='select_stage'][phx-value-id='#{regional.id}']")
    |> render_click()

    html =
      view
      |> element("button[phx-click='move_back'][phx-value-id='#{participation.id}']")
      |> render_click()

    assert html =~ "Moved back to Grassroots Round 2"
    refute html =~ player.first_name

    assert Repo.get!(Cuevolution.Competitions.StageParticipation, participation.id).stage_id ==
             Repo.get_by!(Stage, name: "Grassroots Round 2").id
  end

  test "shows a clear error instead of moving back when matches were played", %{conn: conn} do
    regional = Repo.get_by!(Stage, name: "Regional")
    region = List.first(Accounts.list_regions())
    player = insert(:player, region_id: region.id)

    participation =
      insert(:stage_participation,
        stage_id: regional.id,
        region_id: region.id,
        category: "male",
        player_id: player.id
      )

    group = insert(:group, stage_id: regional.id, category: "male")
    round = insert(:round, stage_id: regional.id, group_id: group.id)
    opponent = insert(:stage_participation, stage_id: regional.id, category: "male")

    insert(:fixture,
      round_id: round.id,
      participant_a_id: participation.id,
      participant_b_id: opponent.id,
      status: "verified"
    )

    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/stages")

    view
    |> element("button[phx-click='select_stage'][phx-value-id='#{regional.id}']")
    |> render_click()

    html =
      view
      |> element("button[phx-click='move_back'][phx-value-id='#{participation.id}']")
      |> render_click()

    assert html =~ "played or recorded matches"
    assert html =~ player.first_name
  end
end
