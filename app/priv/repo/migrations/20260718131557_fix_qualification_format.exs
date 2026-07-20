defmodule Cuevolution.Repo.Migrations.FixQualificationFormat do
  use Ecto.Migration

  def change do
    # --- groups: add venue_id (Grassroots) + category, re-scope uniqueness ---
    alter table(:groups) do
      add :venue_id, references(:venues, type: :binary_id, on_delete: :restrict)
      add :category, :string
    end

    # Backfill any pre-existing dev/seed rows — no reliable inference source,
    # 'male' is an arbitrary but harmless placeholder pre-launch.
    execute(
      "UPDATE groups SET category = 'male' WHERE category IS NULL",
      ""
    )

    alter table(:groups) do
      modify :category, :string, null: false
    end

    create constraint(:groups, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    drop unique_index(:groups, [:stage_id, :region_id, :name])

    # Regional-style groups (no venue): unique per stage/region/category/name.
    create unique_index(:groups, [:stage_id, :region_id, :category, :name],
             where: "venue_id IS NULL",
             name: :groups_region_scoped_unique_index
           )

    # Grassroots-style groups (venue-scoped): unique per stage/venue/category/name.
    create unique_index(:groups, [:stage_id, :venue_id, :category, :name],
             where: "venue_id IS NOT NULL",
             name: :groups_venue_scoped_unique_index
           )

    # --- knockout_brackets: move from group-scoped to stage+category-scoped ---
    drop unique_index(:knockout_brackets, [:group_id])

    alter table(:knockout_brackets) do
      remove :group_id, references(:groups, type: :binary_id, on_delete: :delete_all)
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict)
      add :category, :string
    end

    execute("DELETE FROM knockout_brackets", "")

    alter table(:knockout_brackets) do
      modify :stage_id, :binary_id, null: false
      modify :category, :string, null: false
    end

    create constraint(:knockout_brackets, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    create unique_index(:knockout_brackets, [:stage_id, :category])

    # --- rounds: nullable knockout_bracket_id, exactly-one-of-group-or-bracket ---
    alter table(:rounds) do
      add :knockout_bracket_id,
          references(:knockout_brackets, type: :binary_id, on_delete: :delete_all)
    end

    create index(:rounds, [:knockout_bracket_id])

    # Pre-existing dev/seed rounds predate the group-or-bracket requirement
    # (fixtures cascade via round_id on_delete: :delete_all) — acceptable to
    # drop, this is pre-launch dev data with no real tournament history.
    execute(
      "DELETE FROM rounds WHERE group_id IS NULL AND knockout_bracket_id IS NULL",
      ""
    )

    create constraint(:rounds, :exactly_one_round_context,
             check: """
             (group_id IS NOT NULL AND knockout_bracket_id IS NULL) OR
             (group_id IS NULL AND knockout_bracket_id IS NOT NULL)
             """
           )

    # --- stage_group_configs: admin-configurable group size / advancer count ---
    create table(:stage_group_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_id, references(:stages, type: :binary_id, on_delete: :restrict), null: false
      add :category, :string, null: false
      add :group_size, :integer, null: false, default: 8
      add :advancer_count, :integer, null: false, default: 2

      timestamps()
    end

    create unique_index(:stage_group_configs, [:stage_id, :category])

    create constraint(:stage_group_configs, :category_must_be_valid,
             check: "category IN ('male', 'female', 'team')"
           )

    create constraint(:stage_group_configs, :group_size_must_be_positive, check: "group_size > 0")

    create constraint(:stage_group_configs, :advancer_count_must_be_positive,
             check: "advancer_count > 0"
           )

    execute(
      """
      INSERT INTO stage_group_configs (id, stage_id, category, group_size, advancer_count, inserted_at, updated_at)
      SELECT gen_random_uuid(), s.id, v.category, 8, 2, now(), now()
      FROM stages s
      JOIN (VALUES
        ('Grassroots', 'male'),
        ('Grassroots', 'female'),
        ('Grassroots', 'team'),
        ('Regional', 'male'),
        ('Regional', 'female'),
        ('Regional', 'team')
      ) AS v(stage_name, category) ON v.stage_name = s.name
      """,
      "DELETE FROM stage_group_configs"
    )
  end
end
