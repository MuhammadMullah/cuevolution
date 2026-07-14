defmodule Cuevolution.Repo.Migrations.CreateStages do
  use Ecto.Migration

  def change do
    create table(:stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :order, :integer, null: false

      timestamps()
    end

    create unique_index(:stages, [:name])
    create unique_index(:stages, [:order])

    # Seed the four fixed pipeline stages (spec 006 FR-001). Seeding inside
    # the migration (not priv/repo/seeds.exs) guarantees every environment,
    # including test, has these rows — every other Competitions table FKs
    # into `stages`.
    execute(
      """
      INSERT INTO stages (id, name, "order", inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'Grassroots', 1, now(), now()),
        (gen_random_uuid(), 'Regional', 2, now(), now()),
        (gen_random_uuid(), 'Circuit', 3, now(), now()),
        (gen_random_uuid(), 'Finals', 4, now(), now())
      """,
      "DELETE FROM stages WHERE name IN ('Grassroots', 'Regional', 'Circuit', 'Finals')"
    )
  end
end
