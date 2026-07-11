defmodule Cuevolution.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :date_of_birth, :date, null: false
      add :gender, :string, null: false
      add :email, :string, null: false
      add :mobile_number, :string, null: false
      add :profile_picture_path, :string
      add :location, :string, null: false
      add :country, :string, null: false, default: "KE"
      add :username, :string, null: false
      add :notification_preference, :string, null: false
      add :hashed_password, :string, null: false
      add :anonymized_at, :utc_datetime

      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false

      # No FK constraint yet: the `teams` table doesn't exist until Context 4
      # (Teams), and `teams.captain_id` will forward-reference `players` —
      # the two tables are mutually dependent. This column is plain/indexed
      # for now; Teams' own migration adds the FK constraint once the
      # `teams` table exists (same deferred-FK pattern used for
      # `preferred_venue_id`, see the Venues context).
      add :team_id, :binary_id

      timestamps()
    end

    create unique_index(:players, ["lower(username)"], name: :players_lower_username_index)
    create unique_index(:players, ["lower(email)"], name: :players_lower_email_index)
    create index(:players, [:region_id])
    create index(:players, [:team_id])

    create constraint(:players, :gender_must_be_valid, check: "gender IN ('male', 'female')")

    create constraint(:players, :notification_preference_must_be_valid,
             check: "notification_preference IN ('email', 'sms', 'both')"
           )

    create constraint(:players, :country_must_be_iso_alpha2, check: "country ~ '^[A-Z]{2}$'")
  end
end
