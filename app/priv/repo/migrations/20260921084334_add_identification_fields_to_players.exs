defmodule Cuevolution.Repo.Migrations.AddIdentificationFieldsToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :identification_type, :string
      add :identification_number, :string
    end

    create unique_index(:players, ["lower(identification_number)"],
             name: :players_lower_identification_number_index,
             where: "identification_number IS NOT NULL"
           )

    create constraint(:players, :identification_type_must_be_valid,
             check:
               "identification_type IN ('passport', 'national_id') OR identification_type IS NULL"
           )
  end
end
