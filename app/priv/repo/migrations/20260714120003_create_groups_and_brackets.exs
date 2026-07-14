defmodule Cuevolution.Repo.Migrations.CreateGroupsAndBrackets do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false

      timestamps()
    end

    create index(:groups, [:stage_id, :region_id])
    create unique_index(:groups, [:stage_id, :region_id, :name])

    create table(:group_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      add :stage_participation_id,
          references(:stage_participations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:group_memberships, [:group_id])
    create index(:group_memberships, [:stage_participation_id])
    create unique_index(:group_memberships, [:group_id, :stage_participation_id])

    create table(:knockout_brackets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    # Regional-only, one bracket per group (FR-004).
    create unique_index(:knockout_brackets, [:group_id])
  end
end
