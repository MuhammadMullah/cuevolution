defmodule Cuevolution.Repo.Migrations.AddCompletionDeadlineToStages do
  use Ecto.Migration

  def change do
    alter table(:stages) do
      add :completion_deadline, :date
    end
  end
end
