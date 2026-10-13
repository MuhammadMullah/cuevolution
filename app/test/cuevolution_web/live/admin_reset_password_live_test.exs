defmodule CuevolutionWeb.AdminResetPasswordLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.AdminToken
  alias Cuevolution.Repo

  defp valid_token_for(admin) do
    {encoded_token, token_struct} = AdminToken.build_reset_password_token(admin)
    Repo.insert!(token_struct)
    encoded_token
  end

  defp seconds_ago(seconds) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-seconds, :second)
    |> NaiveDateTime.truncate(:second)
  end

  test "shows the invalid-link state for a garbage token", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/reset-password/not-a-real-token")
    assert html =~ "Link invalid or expired"
  end

  test "shows the invalid-link state for an expired token", %{conn: conn} do
    admin = insert(:admin)
    {encoded_token, token_struct} = AdminToken.build_reset_password_token(admin)

    token_struct
    |> Repo.insert!()
    |> Ecto.Changeset.change(inserted_at: seconds_ago(21 * 60))
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/reset-password/#{encoded_token}")
    assert html =~ "Link invalid or expired"
  end

  test "shows the invalid-link state when the admin has since been suspended", %{conn: conn} do
    admin = insert(:admin)
    token = valid_token_for(admin)

    admin
    |> Ecto.Changeset.change(suspended_at: DateTime.utc_now(:second))
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/reset-password/#{token}")
    assert html =~ "Link invalid or expired"
  end

  test "a setup token can't be used as a reset token", %{conn: conn} do
    admin = insert(:admin)
    {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)
    Repo.insert!(token_struct)

    {:ok, _view, html} = live(conn, ~p"/admin/reset-password/#{encoded_token}")
    assert html =~ "Link invalid or expired"
  end

  test "shows the new-password form for a valid token", %{conn: conn} do
    admin = insert(:admin)
    token = valid_token_for(admin)

    {:ok, _view, html} = live(conn, ~p"/admin/reset-password/#{token}")
    assert html =~ "Choose a new password"
    assert html =~ admin.email
  end

  test "rejects a weak password inline without consuming the token", %{conn: conn} do
    admin = insert(:admin)
    token = valid_token_for(admin)
    {:ok, view, _html} = live(conn, ~p"/admin/reset-password/#{token}")

    html =
      view
      |> form("form", admin: %{"password" => "short", "password_confirmation" => "short"})
      |> render_submit()

    assert html =~ "should be at least"
    assert Accounts.get_admin_by_reset_password_token(token).id == admin.id
  end

  test "rejects a mismatched confirmation inline", %{conn: conn} do
    admin = insert(:admin)
    token = valid_token_for(admin)
    {:ok, view, _html} = live(conn, ~p"/admin/reset-password/#{token}")

    html =
      view
      |> form("form",
        admin: %{"password" => "New-Pass1!", "password_confirmation" => "Other-Pass1!"}
      )
      |> render_submit()

    assert html =~ "does not match"
  end

  test "resetting sets the new password, clears every token and the must-change flag", %{
    conn: conn
  } do
    admin = insert(:admin, must_change_password: true)
    session_token = Accounts.generate_admin_session_token(admin)
    token = valid_token_for(admin)
    {:ok, view, _html} = live(conn, ~p"/admin/reset-password/#{token}")

    html =
      view
      |> form("form",
        admin: %{"password" => "New-Pass1!", "password_confirmation" => "New-Pass1!"}
      )
      |> render_submit()

    assert html =~ "Password reset"
    assert {:ok, reloaded} = Accounts.authenticate_admin(admin.email, "New-Pass1!")
    refute reloaded.must_change_password

    assert {:error, :invalid_credentials} =
             Accounts.authenticate_admin(admin.email, "Valid1!Pass")

    assert Accounts.get_admin_by_reset_password_token(token) == nil
    assert Accounts.get_admin_by_session_token(session_token) == nil
  end
end
