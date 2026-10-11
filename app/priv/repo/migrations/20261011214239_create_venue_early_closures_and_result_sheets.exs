defmodule Cuevolution.Repo.Migrations.CreateVenueEarlyClosuresAndResultSheets do
  use Ecto.Migration

  def change do
    create table(:venue_early_closures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :admin_id, references(:admins, type: :binary_id, on_delete: :restrict), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:venue_early_closures, [:stage_id, :venue_id, :category],
             name: :venue_early_closures_unique_index
           )

    create table(:result_sheets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict), null: false

      add :uploaded_by_admin_id,
          references(:admins, type: :binary_id, on_delete: :restrict),
          null: false

      add :object_key, :string, null: false
      add :content_type, :string, null: false
      add :original_filename, :string, null: false
      add :uploaded_on, :date, null: false

      timestamps()
    end

    create unique_index(:result_sheets, [:venue_id, :stage_id, :uploaded_on],
             name: :result_sheets_unique_index
           )
  end
end
