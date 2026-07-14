defmodule CuevolutionWeb.NotificationLogLiveTest do
  use CuevolutionWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cuevolution.Accounts
  alias Cuevolution.Notifications

  defp log_in_admin(conn) do
    admin = insert(:admin)
    token = Accounts.generate_admin_session_token(admin)
    conn |> init_test_session(%{}) |> put_session(:admin_token, token)
  end

  test "redirects anonymous visitors to admin login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/notifications")
  end

  test "lists notifications and filters by status", %{conn: conn} do
    player = insert(:player, notification_preference: "email", username: "pendingplayer")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})
    notification |> Ecto.Changeset.change(status: "sent") |> Cuevolution.Repo.update!()

    other_player = insert(:player, notification_preference: "sms", username: "smsplayer")
    Notifications.dispatch(other_player, :registration_confirmation, %{})

    conn = log_in_admin(conn)
    {:ok, view, html} = live(conn, ~p"/admin/notifications")

    assert html =~ "pendingplayer"
    assert html =~ "smsplayer"

    html =
      view
      |> element("button[phx-click=filter_status][phx-value-id='sent']")
      |> render_click()

    assert html =~ "pendingplayer"
    refute html =~ "smsplayer"
  end
end
