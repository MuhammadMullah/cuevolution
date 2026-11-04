defmodule CuevolutionWeb.GroupManagementCircuitTest do
  @moduledoc """
  The Circuit stage is drawn and scored from the Groups screen, alongside the
  round-robin stages, rather than on a page of its own.
  """
  use CuevolutionWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.Stage
  alias Cuevolution.Repo

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp as_td(conn), do: log_in_admin(conn, insert(:admin, role: "tournament_director"))

  defp enter(count, category \\ "male") do
    stage = circuit()

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end
  end

  # Clicks through to the Circuit stage tab for `category`.
  defp open_circuit(view, category \\ "male") do
    view |> element("button[phx-value-id='#{circuit().id}']") |> render_click()
    view |> element("button[phx-value-category='#{category}']") |> render_click()
    view
  end

  defp first_fixture(category \\ "male") do
    bracket = Competitions.get_knockout_bracket(circuit().id, category)

    Repo.one!(
      from f in Fixture,
        join: r in Round,
        on: r.id == f.round_id,
        where: r.knockout_bracket_id == ^bracket.id and r.sequence == 1 and f.slot == 1
    )
  end

  describe "the Circuit stage tab" do
    test "appears alongside the round-robin stages", %{conn: conn} do
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/groups")

      assert html =~ "Grassroots"
      assert html =~ "Regional"
      assert html =~ "Circuit"
    end

    test "offers the draw with the entrant count", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = view |> open_circuit() |> render()

      assert html =~ "No Individual Male draw yet" or html =~ "draw yet"
      assert html =~ "Make the draw"
      assert html =~ "8"
    end

    test "all three categories are selectable", %{conn: conn} do
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = view |> open_circuit() |> render()

      for category <- ~w(male female team) do
        assert html =~ "phx-value-category=\"#{category}\""
      end
    end
  end

  describe "drawing from the Groups screen" do
    test "a TD draws and the bracket replaces the prompt", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)

      html = view |> element("button[phx-click='draw_circuit']") |> render_click()

      assert html =~ "Draw made for 8"
      assert html =~ "Winners Round 1"
      assert html =~ "race to 6"
      refute html =~ "Make the draw"
    end

    test "the ladies' draw uses the ladies' race lengths", %{conn: conn} do
      enter(8, "female")

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view, "female")

      html = view |> element("button[phx-click='draw_circuit']") |> render_click()

      assert html =~ "race to 4"
      assert html =~ "race to 3"
    end

    test "an admin who cannot close a stage gets no draw button", %{conn: conn} do
      enter(8)
      admin = insert(:admin, role: "regional_coordinator", region_id: build(:region).id)

      {:ok, view, _html} = live(log_in_admin(conn, admin), ~p"/admin/groups")
      html = view |> open_circuit() |> render()

      refute html =~ "phx-click=\"draw_circuit\""
      assert html =~ "Only a tournament director can make the draw."
    end
  end

  describe "scoring from the Groups screen" do
    setup %{conn: conn} do
      enter(8)
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()
      %{view: view}
    end

    test "tapping a frame marks the match live", %{view: view} do
      fixture = first_fixture()

      view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()

      view
      |> element(
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"
      )
      |> render_click()

      reloaded = Repo.get!(Fixture, fixture.id)
      assert reloaded.status == "live"
      assert reloaded.live_score == %{"a" => 1, "b" => 0}
    end

    test "finishing a match advances both players", %{view: view} do
      fixture = first_fixture()
      winner = fixture.participant_a_id
      loser = fixture.participant_b_id

      view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()

      view
      |> element("button[phx-click='finish_circuit_fixture'][phx-value-winner='#{winner}']")
      |> render_click()

      done = Repo.get!(Fixture, fixture.id)
      assert done.status == "completed"
      assert Repo.get!(Fixture, done.winner_to_fixture_id).participant_a_id == winner
      assert Repo.get!(Fixture, done.loser_to_fixture_id).participant_a_id == loser
    end
  end

  describe "the entrant list before the draw" do
    test "lists everyone entered with no matches played", %{conn: conn} do
      players = enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      html = view |> open_circuit() |> render()

      assert html =~ "entered for the Circuit, none drawn yet"
      assert html =~ "Entered — Individual Male Circuit (8)"

      # every entrant by username, and the matches column reading zero
      for p <- players do
        player = Repo.preload(p, :player).player
        assert html =~ player.username
      end
    end

    test "the list is replaced by the bracket once drawn", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)

      html = view |> element("button[phx-click='draw_circuit']") |> render_click()

      refute html =~ "none drawn yet"
      assert html =~ "Winners Round 1"
    end
  end

  describe "re-dealing the draw" do
    test "an unplayed draw can be re-dealt", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()

      html = view |> element("button[phx-click='redeal_circuit_draw']") |> render_click()

      assert html =~ "Re-dealt 1 of 3"
      assert html =~ "Winners Round 1"
      assert html =~ "2 of 3 re-deals left"
    end

    test "entrants added after a draw are picked up by a redraw", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()

      # four more register after the draw was made
      enter(4)

      html = view |> element("button[phx-click='redeal_circuit_draw']") |> render_click()

      assert html =~ "Re-dealt 1 of 3 — 12 drawn again"
    end

    test "three re-deals are allowed, the fourth is not", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()

      for n <- 1..3 do
        html = view |> element("button[phx-click='redeal_circuit_draw']") |> render_click()
        assert html =~ "Re-dealt #{n} of 3"
      end

      html = render(view)
      assert html =~ "0 of 3 re-deals left"
      refute html =~ "redeal_circuit_draw"

      assert {:error, :redraw_limit_reached} =
               Competitions.reshuffle_circuit_draw(
                 circuit().id,
                 "male",
                 insert(:admin, role: "tournament_director")
               )
    end

    test "once a result is recorded the draw can no longer be re-dealt", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()

      fixture = first_fixture()
      view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()

      view
      |> element(
        "button[phx-click='finish_circuit_fixture'][phx-value-winner='#{fixture.participant_a_id}']"
      )
      |> render_click()

      refute render(view) =~ "redeal_circuit_draw"
      assert Competitions.circuit_redraws_remaining(circuit().id, "male") == 0
    end
  end

  describe "the selected tab survives a reload" do
    test "the stage and category are reflected in the URL", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      open_circuit(view, "female")

      # Two clicks, two patches: the stage, then the category.
      assert_patch(view)
      path = assert_patch(view)

      assert path =~ "stage=Circuit"
      assert path =~ "category=female"
      # The region rides along so switching back to a round-robin stage keeps it.
      assert path =~ "region="
    end

    test "landing on that URL directly opens the same tab", %{conn: conn} do
      enter(8, "female")

      {:ok, _view, html} =
        live(as_td(conn), ~p"/admin/groups?stage=Circuit&category=female")

      assert html =~ "No Individual Female draw yet"
      # Grassroots content is not what we get back.
      refute html =~ "Unassigned participants"
    end

    test "a refresh keeps the Circuit tab rather than resetting to Grassroots", %{conn: conn} do
      enter(8)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      open_circuit(view)
      assert_patch(view)
      path = assert_patch(view)

      # A reload is a fresh mount at the same URL.
      {:ok, _view, html} = live(as_td(conn), path)

      assert html =~ "No Individual Male draw yet"
    end

    test "an unknown stage falls back to the first tab", %{conn: conn} do
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/groups?stage=Nonsense&category=male")

      refute html =~ "draw yet"
      assert html =~ "Grassroots"
    end

    test "a category the stage does not run falls back", %{conn: conn} do
      # Grassroots is male-only; asking for female should not blow up.
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/groups?stage=Grassroots&category=female")

      assert html =~ "Grassroots"
    end
  end

  describe "bracket views" do
    setup %{conn: conn} do
      enter(16)
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()
      %{view: view}
    end

    test "full chart is the default and shows every lane", %{view: view} do
      html = render(view)

      assert html =~ "Full chart"
      assert html =~ "By stage"
      assert html =~ "List"
      assert html =~ "Winners&#39; side" or html =~ "Winners' side"
      assert html =~ "Losers&#39; side" or html =~ "Losers' side"
    end

    test "matches are numbered M1 upwards across the whole bracket", %{view: view} do
      html = render(view)

      # 16 players: 8 + 4 + 4 + 4 + 4 + 2 + 1 = 27 matches.
      assert html =~ "M1"
      assert html =~ "M27"
    end

    test "each match says where its loser goes", %{view: view} do
      html = render(view)

      assert html =~ "Loser to M"
      # The losers' bracket is the end of the road.
      assert html =~ "Loser is out"
    end

    test "connector lines join each round to the next", %{view: view} do
      html = render(view)

      # The elbow that brackets two cards into one, and the straight carry.
      assert html =~ "rounded-r-md border-2 border-l-0 border-ink-300"
      assert html =~ "border-t-2 border-ink-300"
    end

    test "the winners'-side player is shaded on a crossover card", %{view: view} do
      html = render(view)

      assert html =~ "bg-green-50"
      assert html =~ "Down from the winners&#39; side" or html =~ "Down from the winners' side"
    end

    test "by stage narrows to one side at a time", %{view: view} do
      view |> element("button[phx-value-view='stage']") |> render_click()
      html = view |> element("button[phx-value-side='losers']") |> render_click()

      assert html =~ "Losers Round 1"
      refute html =~ "Winners Round 1"

      html = view |> element("button[phx-value-side='winners']") |> render_click()
      assert html =~ "Winners Round 1"
      refute html =~ "Losers Round 1"
    end

    test "finals shows the knockout rounds only", %{view: view} do
      view |> element("button[phx-value-view='stage']") |> render_click()
      html = view |> element("button[phx-value-side='finals']") |> render_click()

      assert html =~ "Final"
      refute html =~ "Winners Round 1"
    end

    test "list view groups matches by round with progress", %{view: view} do
      html = view |> element("button[phx-value-view='list']") |> render_click()

      assert html =~ "All 27"
      assert html =~ "Up next"
      assert html =~ "of 8 played"
    end

    test "list filters narrow to live matches", %{view: view} do
      # Nothing is live yet, so the live filter empties the list.
      html = view |> element("button[phx-value-view='list']") |> render_click()
      assert html =~ "Winners Round 1"

      html = view |> element("button[phx-value-filter='live']") |> render_click()
      refute html =~ "Loser to M"
    end

    test "zoom switches between fit and a fixed percentage", %{view: view} do
      html = view |> element("button[phx-value-zoom='100']") |> render_click()
      assert html =~ "zoom:1.0"

      html = view |> element("button[phx-value-zoom='fit']") |> render_click()
      refute html =~ "zoom:"
    end
  end

  describe "completing a match" do
    setup %{conn: conn} do
      enter(8)
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()
      fixture = first_fixture()
      view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()
      %{view: view, fixture: fixture}
    end

    test "before the race is reached it explains what to do", %{view: view} do
      html = render(view)

      assert html =~ "First to 6 frames wins"
      refute html =~ "Complete match"
      # Early finish is still possible, but worded as the exception.
      assert html =~ "Award"
    end

    test "scoring an unscheduled match stamps its start time", %{view: view, fixture: fixture} do
      assert Repo.get!(Fixture, fixture.id).scheduled_at == nil

      view
      |> element(
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"
      )
      |> render_click()

      stamped = Repo.get!(Fixture, fixture.id).scheduled_at
      assert stamped, "the first frame should record when the match started"
      assert DateTime.diff(DateTime.utc_now(), stamped) < 60
    end

    test "a time already set is not overwritten by scoring", %{view: view, fixture: fixture} do
      tomorrow = Competitions.today_in_eat() |> Date.add(1) |> Date.to_iso8601()

      view
      |> form("form[phx-submit='schedule_circuit_fixture']", %{
        slot: %{id: fixture.id, date: tomorrow, time: "19:30"}
      })
      |> render_submit()

      scheduled = Repo.get!(Fixture, fixture.id).scheduled_at

      view
      |> element(
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"
      )
      |> render_click()

      assert Repo.get!(Fixture, fixture.id).scheduled_at == scheduled
    end

    test "the panel stays open across frames so scoring is one tap each", %{
      view: view,
      fixture: fixture
    } do
      plus =
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"

      # Three frames in a row with no re-opening in between.
      for _ <- 1..3, do: view |> element(plus) |> render_click()

      assert Repo.get!(Fixture, fixture.id).live_score == %{"a" => 3, "b" => 0}
      assert render(view) =~ "circuit_frame"
    end

    test "reaching the race offers Complete match", %{view: view, fixture: fixture} do
      plus =
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"

      for _ <- 1..6, do: view |> element(plus) |> render_click()

      html = render(view)
      assert html =~ "Race complete"
      assert html =~ "Complete match"
    end

    test "a frame tapped after the result is recorded cannot un-finish the match", %{
      view: view,
      fixture: fixture
    } do
      plus =
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"

      for _ <- 1..6, do: view |> element(plus) |> render_click()

      view
      |> element(
        "button[phx-click='finish_circuit_fixture'][phx-value-winner='#{fixture.participant_a_id}']"
      )
      |> render_click()

      # A tap that lands after completion — a double-tap, or an event queued
      # before the re-render — must not flip the fixture back to "live", or
      # every later attempt to record it fails on the unique constraint.
      assert {:error, :already_recorded} =
               Competitions.update_live_score(
                 Repo.get!(Fixture, fixture.id),
                 insert(:admin, role: "tournament_director"),
                 %{"a" => 1, "b" => 0}
               )

      reloaded = Repo.get!(Fixture, fixture.id)
      assert reloaded.status == "completed"
      assert reloaded.live_score == nil
    end

    test "Complete match records the result and advances both players", %{
      view: view,
      fixture: fixture
    } do
      plus =
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"

      for _ <- 1..6, do: view |> element(plus) |> render_click()

      view
      |> element(
        "button[phx-click='finish_circuit_fixture'][phx-value-winner='#{fixture.participant_a_id}']"
      )
      |> render_click()

      done = Repo.get!(Fixture, fixture.id)
      assert done.status == "completed"
      assert done.result_id

      assert Repo.get!(Fixture, done.winner_to_fixture_id).participant_a_id ==
               fixture.participant_a_id
    end
  end

  describe "setting a match start time" do
    setup %{conn: conn} do
      enter(8)
      {:ok, view, _html} = live(as_td(conn), ~p"/admin/groups")
      view = open_circuit(view)
      view |> element("button[phx-click='draw_circuit']") |> render_click()
      fixture = first_fixture()
      view |> element("button[phx-value-id='#{fixture.id}']") |> render_click()

      # Tomorrow, so the test never trips the past-date guard at a day boundary.
      tomorrow = Competitions.today_in_eat() |> Date.add(1) |> Date.to_iso8601()
      %{view: view, fixture: fixture, tomorrow: tomorrow}
    end

    defp set_time(view, fixture, date, time) do
      view
      |> form("form[phx-submit='schedule_circuit_fixture']", %{
        slot: %{id: fixture.id, date: date, time: time}
      })
      |> render_submit()
    end

    test "the TD sets a start time in local time", %{
      view: view,
      fixture: fixture,
      tomorrow: tomorrow
    } do
      html = set_time(view, fixture, tomorrow, "19:30")

      assert html =~ "Match time saved."
      # 19:30 local (EAT) is 16:30 UTC.
      assert DateTime.to_iso8601(Repo.get!(Fixture, fixture.id).scheduled_at) =~ "16:30"
    end

    test "the start time shows on the match card in local time", %{
      view: view,
      fixture: fixture,
      tomorrow: tomorrow
    } do
      set_time(view, fixture, tomorrow, "19:30")

      assert render(view) =~ "19:30"
    end

    test "there is no duration field any more", %{view: view} do
      html = render(view)

      refute html =~ "duration_minutes"
      refute html =~ "Duration"
      assert html =~ "Start time"
    end

    test "the date picker will not offer a past date", %{view: view} do
      today = Date.to_iso8601(Competitions.today_in_eat())

      assert render(view) =~ ~s(min="#{today}")
    end

    test "a past date is refused server-side too", %{view: view, fixture: fixture} do
      yesterday = Competitions.today_in_eat() |> Date.add(-1) |> Date.to_iso8601()

      html = set_time(view, fixture, yesterday, "19:30")

      assert html =~ "cannot be scheduled before today"
      assert Repo.get!(Fixture, fixture.id).scheduled_at == nil
    end

    test "today is still allowed, so a time can be corrected mid-session", %{
      view: view,
      fixture: fixture
    } do
      today = Date.to_iso8601(Competitions.today_in_eat())

      html = set_time(view, fixture, today, "23:30")

      assert html =~ "Match time saved."
      assert Repo.get!(Fixture, fixture.id).scheduled_at
    end

    test "a date with no start time leaves the match unscheduled", %{
      view: view,
      fixture: fixture,
      tomorrow: tomorrow
    } do
      set_time(view, fixture, tomorrow, "")

      assert Repo.get!(Fixture, fixture.id).scheduled_at == nil
    end

    test "clearing the time puts the match back in the unscheduled pile", %{
      view: view,
      fixture: fixture,
      tomorrow: tomorrow
    } do
      set_time(view, fixture, tomorrow, "19:30")
      set_time(view, fixture, "", "")

      assert Repo.get!(Fixture, fixture.id).scheduled_at == nil
    end

    test "a played match's time is locked", %{view: view, fixture: fixture} do
      plus =
        "button[phx-click='circuit_frame'][phx-value-id='#{fixture.id}'][phx-value-side='a'][phx-value-delta='1']"

      for _ <- 1..6, do: view |> element(plus) |> render_click()

      view
      |> element(
        "button[phx-click='finish_circuit_fixture'][phx-value-winner='#{fixture.participant_a_id}']"
      )
      |> render_click()

      assert {:error, :locked} =
               Competitions.schedule_bracket_fixture(
                 Repo.get!(Fixture, fixture.id),
                 insert(:admin, role: "tournament_director"),
                 %{"date" => Date.to_iso8601(Competitions.today_in_eat()), "time" => "19:30"}
               )
    end
  end

  describe "the round-robin stages are untouched" do
    test "Grassroots still shows its own screen, not a bracket", %{conn: conn} do
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/groups")

      # Grassroots is the default tab.
      refute html =~ "Winners' side"
      assert html =~ "Groups"
    end
  end
end
