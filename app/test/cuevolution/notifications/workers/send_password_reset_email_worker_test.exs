defmodule Cuevolution.Notifications.Workers.SendPasswordResetEmailWorkerTest do
  use Cuevolution.DataCase, async: true

  import Swoosh.TestAssertions

  alias Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker

  test "sends the reset-password email with the given URL" do
    player = insert(:player, notification_preference: "sms")

    assert :ok =
             perform_job(SendPasswordResetEmailWorker, %{
               "player_id" => player.id,
               "reset_url" => "https://cuevolution.test/reset-password/abc123"
             })

    assert_email_sent(fn email ->
      email.subject == "Reset your password" and
        {"#{player.first_name} #{player.last_name}", player.email} in email.to and
        email.html_body =~ "https://cuevolution.test/reset-password/abc123"
    end)
  end

  test "is a no-op if the player no longer exists" do
    assert :ok =
             perform_job(SendPasswordResetEmailWorker, %{
               "player_id" => Ecto.UUID.generate(),
               "reset_url" => "https://cuevolution.test/reset-password/abc123"
             })

    refute_email_sent()
  end
end
