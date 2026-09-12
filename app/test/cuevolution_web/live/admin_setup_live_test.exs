defmodule CuevolutionWeb.AdminSetupLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.AdminToken
  alias Cuevolution.Repo

  test "shows an invalid-link message for a garbage token", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/setup/garbage")
    assert html =~ "Link invalid or expired"
  end

  test "shows the form with the invited admin's role for a valid token", %{conn: conn} do
    admin = insert(:admin, hashed_password: nil, role: "regional_coordinator")
    {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)
    Repo.insert!(token_struct)

    {:ok, _view, html} = live(conn, ~p"/admin/setup/#{encoded_token}")

    assert html =~ "Regional Coordinator"
    assert html =~ admin.email
  end

  test "completing setup sets the password and mobile number, then the admin can log in", %{
    conn: conn
  } do
    admin = insert(:admin, hashed_password: nil, role: "venue_representative")
    {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)
    Repo.insert!(token_struct)

    {:ok, view, _html} = live(conn, ~p"/admin/setup/#{encoded_token}")

    html =
      view
      |> form("form", %{
        "admin" => %{
          "password" => "New-Pass1!",
          "password_confirmation" => "New-Pass1!",
          "mobile_number" => "0712345678"
        }
      })
      |> render_submit()

    assert html =~ "Account ready"
    assert {:ok, _} = Accounts.authenticate_admin(admin.email, "New-Pass1!")
  end

  test "shows an error for a mismatched password confirmation", %{conn: conn} do
    admin = insert(:admin, hashed_password: nil, role: "venue_representative")
    {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)
    Repo.insert!(token_struct)

    {:ok, view, _html} = live(conn, ~p"/admin/setup/#{encoded_token}")

    html =
      view
      |> form("form", %{
        "admin" => %{
          "password" => "New-Pass1!",
          "password_confirmation" => "Different1!",
          "mobile_number" => "0712345678"
        }
      })
      |> render_submit()

    assert html =~ "does not match"
  end
end
