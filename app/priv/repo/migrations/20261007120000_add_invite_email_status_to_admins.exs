defmodule Cuevolution.Repo.Migrations.AddInviteEmailStatusToAdmins do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :invite_email_status, :string, default: "pending", null: false
      add :invite_email_failed_at, :utc_datetime
    end
  end
end
