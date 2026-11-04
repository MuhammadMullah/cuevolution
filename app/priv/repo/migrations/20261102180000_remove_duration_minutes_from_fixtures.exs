defmodule Cuevolution.Repo.Migrations.RemoveDurationMinutesFromFixtures do
  use Ecto.Migration

  @moduledoc """
  Drops `fixtures.duration_minutes` again.

  Added two migrations ago so a tournament director could allocate a slot
  length; the committee decided a start time alone is what they want to set,
  so the column goes rather than sitting unused and half-explained. The real
  elapsed time of a match is still derivable from its result timestamps.
  """

  def up do
    drop constraint(:fixtures, :duration_minutes_positive)

    alter table(:fixtures) do
      remove :duration_minutes
    end
  end

  def down do
    alter table(:fixtures) do
      add :duration_minutes, :integer
    end

    create constraint(:fixtures, :duration_minutes_positive,
             check:
               "duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 600)"
           )
  end
end
