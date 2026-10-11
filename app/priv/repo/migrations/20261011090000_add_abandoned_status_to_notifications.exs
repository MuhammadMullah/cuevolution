defmodule Cuevolution.Repo.Migrations.AddAbandonedStatusToNotifications do
  use Ecto.Migration

  def change do
    drop constraint(:notifications, :status_must_be_valid)

    create constraint(:notifications, :status_must_be_valid,
             check: "status IN ('pending', 'sending', 'sent', 'failed', 'abandoned')"
           )
  end
end
