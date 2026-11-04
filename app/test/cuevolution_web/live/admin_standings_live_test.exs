defmodule CuevolutionWeb.Admin.StandingsLiveTest do
  @moduledoc """
  The per-circuit standings table from the SP Points & Standings brief
  (Nov 2026) — provisional while the circuit runs, final once it is over.
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
  alias Ecto.Adapters.SQL.Sandbox

  defp circuit, do: Repo.get_by!(Stage, name: "Circuit")

  defp log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  defp as_td(conn), do: log_in_admin(conn, insert(:admin, role: "tournament_director"))

  defp bracket_for(category, count) do
    stage = circuit()
    admin = insert(:admin, role: "tournament_director")

    for _ <- 1..count do
      insert(:stage_participation, stage_id: stage.id, category: category)
    end

    {:ok, %{bracket: bracket}} = Competitions.draw_circuit_bracket(stage.id, category, admin)
    %{bracket: bracket, admin: admin}
  end

  defp play_round(bracket, admin, code) do
    fixtures =
      Repo.all(
        from f in Fixture,
          join: r in Round,
          on: r.id == f.round_id,
          where:
            r.knockout_bracket_id == ^bracket.id and r.code == ^code and f.bye == false and
              is_nil(f.result_id),
          order_by: f.slot
      )

    for f <- fixtures, f.participant_a_id && f.participant_b_id do
      Competitions.record_result(f, admin, %{
        "winner_participation_id" => f.participant_a_id,
        "score" => %{"a" => 6, "b" => 2}
      })
    end

    fixtures
  end

  defp play_out(bracket, admin) do
    codes =
      Repo.all(
        from r in Round,
          where: r.knockout_bracket_id == ^bracket.id,
          order_by: r.sequence,
          select: r.code
      )

    Enum.each(codes, &play_round(bracket, admin, &1))
  end

  describe "reaching the table" do
    test "it is linked from the admin nav", %{conn: conn} do
      {:ok, _view, html} = live(as_td(conn), ~p"/admin/dashboard")

      assert html =~ ~s(href="/admin/standings")
    end

    test "an anonymous visitor is redirected to the admin login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/standings")
    end
  end

  describe "the brief's columns" do
    test "the provisional view carries Status, the final view does not", %{conn: conn} do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)
      play_round(bracket, admin, "W1")

      {:ok, _view, html} = live(as_td(conn), ~p"/admin/standings")

      assert html =~ "Provisional"
      assert html =~ "Status"
      assert html =~ "Winners side"
      assert html =~ "Losers side"

      play_out(bracket, admin)

      {:ok, _view, final} = live(as_td(conn), ~p"/admin/standings")

      assert final =~ "Final"
      refute final =~ "Winners side"
    end

    test "every column the brief lists is present", %{conn: conn} do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)
      play_out(bracket, admin)

      {:ok, _view, html} = live(as_td(conn), ~p"/admin/standings")

      for header <- [
            "Pos",
            "Player",
            "Region",
            "Finish",
            "Racks won",
            "Racks played",
            "Rack-win %",
            "SP Points"
          ] do
        assert html =~ header, "the #{header} column is missing"
      end
    end

    test "rack-win % is shown to one decimal place", %{conn: conn} do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)
      play_out(bracket, admin)

      {:ok, _view, html} = live(as_td(conn), ~p"/admin/standings")

      # Every match here was 6-2, so a winner's share is 6/8 = 75.0%.
      assert html =~ "75.0%"
    end
  end

  describe "shared positions" do
    setup do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)
      play_out(bracket, admin)
      %{standings: Competitions.circuit_standings(circuit().id, "male")}
    end

    test "the table locks, bands share their points, and every place is accounted for",
         %{standings: standings} do
      assert standings.state == :final

      bands = Enum.group_by(standings.rows, & &1.position)

      for {position, band} <- bands do
        points = band |> Enum.map(& &1.points) |> Enum.uniq()

        assert length(points) == 1,
               "position #{inspect(position)} has mixed points #{inspect(points)}"

        {from, to} = position

        assert to - from + 1 == length(band),
               "band #{from}-#{to} holds #{length(band)} players"
      end

      covered =
        bands |> Map.keys() |> Enum.flat_map(fn {from, to} -> Enum.to_list(from..to) end)

      assert Enum.sort(covered) == Enum.to_list(1..16)
    end

    test "a shared position prints with an equals sign", %{standings: standings} do
      semis = Enum.filter(standings.rows, &(&1.finish == :semi_finalist))

      assert length(semis) == 2
      assert Enum.all?(semis, &(Competitions.position_label(&1, :final) == "3="))
      assert Competitions.position_label(hd(standings.rows), :final) == "1"
    end
  end

  describe "ranking order" do
    test "SP Points first, then rack-win %" do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)
      play_out(bracket, admin)

      rows = Competitions.circuit_standings(circuit().id, "male").rows

      keys = Enum.map(rows, &{-&1.points, -(&1.rack_win_pct || -1)})
      assert keys == Enum.sort(keys), "the table is not in the published order"
    end
  end

  describe "live updates" do
    test "a result recorded elsewhere updates the table", %{conn: conn} do
      %{bracket: bracket, admin: admin} = bracket_for("male", 16)

      {:ok, view, _html} = live(as_td(conn), ~p"/admin/standings")

      parent = self()

      Task.async(fn ->
        Sandbox.allow(Repo, parent, self())
        play_round(bracket, admin, "W1")
      end)
      |> Task.await()

      # Winning the opening round guarantees at least 65th — 5 points.
      assert render(view) =~ "5"
    end
  end
end
