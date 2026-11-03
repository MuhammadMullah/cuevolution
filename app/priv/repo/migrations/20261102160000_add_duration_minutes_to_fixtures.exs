defmodule Cuevolution.Repo.Migrations.AddDurationMinutesToFixtures do
  use Ecto.Migration

  @moduledoc """
  How long a match is expected to take, so a tournament director can allocate
  a slot rather than only a start time (spec 014).

  `scheduled_at` has always carried the start; without a duration there is no
  way to say when a table frees up, which is the actual question when three
  days of play are being fitted around a fixed number of tables.

  Expected, not actual: the real elapsed time is derivable from the result's
  timestamps. This is the allocation the TD makes in advance.
  """

  def change do
    alter table(:fixtures) do
      add :duration_minutes, :integer
    end

    create constraint(:fixtures, :duration_minutes_positive,
             check:
               "duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 600)"
           )
  end
end
