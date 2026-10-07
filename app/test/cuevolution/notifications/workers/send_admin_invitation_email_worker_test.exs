defmodule Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorkerTest do
  use Cuevolution.DataCase, async: true

  import Swoosh.TestAssertions

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker
  alias Cuevolution.Repo

  test "sends the invitation email and marks the admin's invite email as sent" do
    admin =
      insert(:admin,
        hashed_password: nil,
        role: "venue_representative",
        invite_email_status: "pending"
      )

    assert :ok =
             perform_job(SendAdminInvitationEmailWorker, %{
               "admin_id" => admin.id,
               "setup_url" => "https://cuevolution.test/admin/setup/abc123"
             })

    assert_email_sent(fn email ->
      {nil, admin.email} in email.to or admin.email in Enum.map(email.to, &elem(&1, 1))
    end)

    updated = Repo.get!(Admin, admin.id)
    refute Admin.invite_email_failed?(updated)
    assert updated.invite_email_status == "sent"
  end

  test "resets a previously failed status back to sent once delivery succeeds" do
    admin =
      insert(:admin,
        hashed_password: nil,
        role: "venue_representative",
        invite_email_status: "failed",
        invite_email_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    assert :ok =
             perform_job(SendAdminInvitationEmailWorker, %{
               "admin_id" => admin.id,
               "setup_url" => "https://cuevolution.test/admin/setup/abc123"
             })

    updated = Repo.get!(Admin, admin.id)
    assert updated.invite_email_status == "sent"
    assert updated.invite_email_failed_at == nil
  end

  test "is a no-op if the admin no longer exists" do
    assert :ok =
             perform_job(SendAdminInvitationEmailWorker, %{
               "admin_id" => Ecto.UUID.generate(),
               "setup_url" => "https://cuevolution.test/admin/setup/abc123"
             })

    refute_email_sent()
  end
end
