defmodule CuevolutionWeb.AdminDirectoryExportControllerTest do
  use CuevolutionWeb.ConnCase, async: true

  alias Cuevolution.Accounts

  defp log_in_admin(conn, role \\ "super_admin") do
    admin = insert(:admin, role: role)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    conn = get(conn, ~p"/admin/directory/export.csv")
    assert redirected_to(conn) == ~p"/admin/login"
  end

  test "denies admins without the view_directory permission", %{conn: conn} do
    conn = conn |> log_in_admin("venue_representative") |> get(~p"/admin/directory/export.csv")

    assert redirected_to(conn) == ~p"/admin/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "don't have access"
  end

  test "exports filtered players as CSV in the Full Name(@username) format", %{conn: conn} do
    region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
    region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

    player_a =
      insert(:player,
        region_id: region_a.id,
        first_name: "Mohamed",
        last_name: "Ali",
        username: "muhammadmullah16"
      )

    player_b = insert(:player, region_id: region_b.id, username: "otherplayer")

    conn =
      conn
      |> log_in_admin()
      |> get(~p"/admin/directory/export.csv?region_id=#{region_a.id}")

    assert response_content_type(conn, :csv) =~ "text/csv"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="directory-all-#{Date.utc_today()}.csv")
           ]

    body = response(conn, 200)
    assert body =~ "#{player_a.first_name} #{player_a.last_name}(@#{player_a.username})"
    refute body =~ player_b.username
  end

  test "applies filters submitted the way the directory page's form actually submits them (nested under filter[...])",
       %{conn: conn} do
    region_a = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "nairobi-a")
    region_b = Cuevolution.Repo.get_by!(Cuevolution.Accounts.Region, slug: "coast")

    player_a = insert(:player, region_id: region_a.id, username: "formsubmitplayer")
    player_b = insert(:player, region_id: region_b.id, username: "otherformplayer")

    conn =
      conn
      |> log_in_admin()
      |> get(~p"/admin/directory/export.csv?filter[region_id]=#{region_a.id}")

    body = response(conn, 200)
    assert body =~ player_a.username
    refute body =~ player_b.username
  end

  test "exports teams as CSV with an inline, semicolon-joined roster", %{conn: conn} do
    team = insert(:team, name: "Westlands Cue Kings")

    member_a =
      insert(:player,
        team_id: team.id,
        region_id: team.region_id,
        first_name: "Amina",
        last_name: "Otieno",
        username: "amina_o"
      )

    member_b =
      insert(:player,
        team_id: team.id,
        region_id: team.region_id,
        first_name: "Brian",
        last_name: "Kip",
        username: "brian_k"
      )

    conn =
      conn
      |> log_in_admin()
      |> get(~p"/admin/directory/export.csv?kind=team")

    body = response(conn, 200)
    assert body =~ "Team,Roster"
    assert body =~ team.name

    assert body =~
             "#{member_a.first_name} #{member_a.last_name}(@#{member_a.username}); " <>
               "#{member_b.first_name} #{member_b.last_name}(@#{member_b.username})"
  end

  test "prefixes a formula-like team name so it can't execute when opened in a spreadsheet", %{
    conn: conn
  } do
    insert(:team, name: "=SUM(A1:A9)")

    conn =
      conn
      |> log_in_admin()
      |> get(~p"/admin/directory/export.csv?kind=team")

    body = response(conn, 200)
    assert body =~ "'=SUM(A1:A9)"
  end

  test "exports as a valid XLSX file", %{conn: conn} do
    insert(:player, first_name: "Mohamed", last_name: "Ali", username: "muhammadmullah16")

    conn =
      conn
      |> log_in_admin()
      |> get(~p"/admin/directory/export.xlsx")

    assert response_content_type(conn, :xlsx) =~
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="directory-all-#{Date.utc_today()}.xlsx")
           ]

    <<"PK", _rest::binary>> = response(conn, 200)
  end
end
