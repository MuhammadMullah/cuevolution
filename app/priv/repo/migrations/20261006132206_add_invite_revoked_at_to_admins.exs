defmodule Cuevolution.Repo.Migrations.AddInviteRevokedAtToAdmins do
  use Ecto.Migration

  def change do
    alter table(:admins) do
      add :invite_revoked_at, :utc_datetime
    end
  end
end
