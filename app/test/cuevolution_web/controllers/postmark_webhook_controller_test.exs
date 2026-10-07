defmodule CuevolutionWeb.PostmarkWebhookControllerTest do
  use CuevolutionWeb.ConnCase

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo

  @valid_auth Plug.BasicAuth.encode_basic_auth("postmark", "postmark-webhook-dev")

  defp authed(conn), do: put_req_header(conn, "authorization", @valid_auth)

  test "rejects a request with no credentials", %{conn: conn} do
    conn = post(conn, ~p"/webhooks/postmark", %{"RecordType" => "Bounce", "Email" => "x@y.com"})

    assert conn.status == 401
  end

  test "rejects a request with the wrong credentials", %{conn: conn} do
    conn =
      conn
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("postmark", "wrong-password")
      )
      |> post(~p"/webhooks/postmark", %{"RecordType" => "Bounce", "Email" => "x@y.com"})

    assert conn.status == 401
  end

  test "accepts an unrecognized RecordType without error", %{conn: conn} do
    conn =
      conn
      |> authed()
      |> post(~p"/webhooks/postmark", %{"RecordType" => "Delivery", "Email" => "x@y.com"})

    assert conn.status == 200
  end

  test "a bounce for a pending admin invite marks it failed", %{conn: conn} do
    admin =
      insert(:admin,
        hashed_password: nil,
        role: "venue_representative",
        invite_email_status: "sent"
      )

    conn =
      conn
      |> authed()
      |> post(~p"/webhooks/postmark", %{
        "RecordType" => "Bounce",
        "Email" => admin.email,
        "Type" => "HardBounce",
        "MessageID" => "abc-123",
        "Description" => "mailbox does not exist"
      })

    assert conn.status == 200

    updated = Repo.get!(Admin, admin.id)
    assert updated.invite_email_status == "failed"
    assert updated.invite_email_failed_at
  end

  test "a bounce for the most recently sent notification marks it failed", %{conn: conn} do
    player = insert(:player, notification_preference: "email")
    [notification] = Notifications.dispatch(player, :registration_confirmation, %{})
    notification |> Ecto.Changeset.change(status: "sent") |> Repo.update!()

    conn =
      conn
      |> authed()
      |> post(~p"/webhooks/postmark", %{
        "RecordType" => "SpamComplaint",
        "Email" => player.email,
        "Type" => "SpamComplaint"
      })

    assert conn.status == 200

    updated = Repo.get!(Notification, notification.id)
    assert updated.status == "failed"
  end

  test "a bounce for an unknown email is a no-op, not an error", %{conn: conn} do
    conn =
      conn
      |> authed()
      |> post(~p"/webhooks/postmark", %{
        "RecordType" => "Bounce",
        "Email" => "nobody-tracked@example.com",
        "Type" => "HardBounce"
      })

    assert conn.status == 200
  end
end
