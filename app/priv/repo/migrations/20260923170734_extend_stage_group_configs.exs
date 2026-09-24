defmodule Cuevolution.Repo.Migrations.ExtendStageGroupConfigs do
  use Ecto.Migration

  def change do
    alter table(:stage_group_configs) do
      add :target_group_size, :integer, null: false, default: 8
      add :minimum_group_size, :integer, null: false, default: 6
      add :minimum_entrants, :integer, null: false, default: 4
      add :extra_qualifier_count, :integer, null: false, default: 0
    end

    create constraint(:stage_group_configs, :target_group_size_must_be_positive,
             check: "target_group_size > 0"
           )

    create constraint(:stage_group_configs, :minimum_group_size_must_be_positive,
             check: "minimum_group_size > 0"
           )

    create constraint(:stage_group_configs, :minimum_entrants_must_be_positive,
             check: "minimum_entrants > 0"
           )

    create constraint(:stage_group_configs, :extra_qualifier_count_must_be_non_negative,
             check: "extra_qualifier_count >= 0"
           )
  end
end
