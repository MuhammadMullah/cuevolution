defmodule CuevolutionWeb.ResetPasswordLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.PlayerToken
  alias Cuevolution.Repo

  defp valid_token_for(player) do
    {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)
    Repo.insert!(token_struct)
    encoded_token
  end

  test "shows the invalid-link state for a garbage token", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/reset-password/not-a-real-token")
    assert html =~ "Link invalid or expired"
  end

  test "shows the invalid-link state for an expired token", %{conn: conn} do
    player = insert(:player)
    {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)

    token_struct
    |> Repo.insert!()
    |> Ecto.Changeset.change(inserted_at: seconds_ago(21 * 60))
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/reset-password/#{encoded_token}")
    assert html =~ "Link invalid or expired"
  end

  test "shows the new-password form for a valid token", %{conn: conn} do
    player = insert(:player)
    token = valid_token_for(player)

    {:ok, _view, html} = live(conn, ~p"/reset-password/#{token}")
    assert html =~ "Choose a new password"
  end

  test "rejects a weak password inline without consuming the token", %{conn: conn} do
    player = insert(:player)
    token = valid_token_for(player)

    {:ok, view, _html} = live(conn, ~p"/reset-password/#{token}")

    html =
      view
      |> form("form", player: %{"password" => "short", "password_confirmation" => "short"})
      |> render_submit()

    assert html =~ "should be at least"
    assert Accounts.get_player_by_reset_password_token(token).id == player.id
  end

  test "rejects a mismatched confirmation inline", %{conn: conn} do
    player = insert(:player)
    token = valid_token_for(player)

    {:ok, view, _html} = live(conn, ~p"/reset-password/#{token}")

    html =
      view
      |> form("form", player: %{"password" => "New-Pass1!", "password_confirmation" => "Nope1!"})
      |> render_submit()

    assert html =~ "does not match"
  end

  test "a successful reset shows the done state and consumes the token", %{conn: conn} do
    player = insert(:player)
    token = valid_token_for(player)

    {:ok, view, _html} = live(conn, ~p"/reset-password/#{token}")

    html =
      view
      |> form("form",
        player: %{"password" => "New-Pass1!", "password_confirmation" => "New-Pass1!"}
      )
      |> render_submit()

    assert html =~ "Password reset"

    assert Bcrypt.verify_pass(
             "New-Pass1!",
             Repo.get!(Cuevolution.Accounts.Player, player.id).hashed_password
           )

    assert Accounts.get_player_by_reset_password_token(token) == nil
  end

  defp seconds_ago(seconds) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-seconds, :second)
    |> NaiveDateTime.truncate(:second)
  end
end
