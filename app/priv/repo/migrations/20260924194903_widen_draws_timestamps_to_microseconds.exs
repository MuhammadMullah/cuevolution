defmodule Cuevolution.Repo.Migrations.WidenDrawsTimestampsToMicroseconds do
  use Ecto.Migration

  # `latest_draw/3` (Competitions) picks the current draw for a
  # stage/venue/category by `ORDER BY inserted_at DESC LIMIT 1`, with no
  # secondary tiebreaker. `draws.inserted_at` was second-precision, so a
  # redraw performed within the same second as an earlier state change on
  # the same draw (dealt/approved/published all happening quickly) could
  # tie with the superseded draw's timestamp, and Postgres doesn't
  # guarantee which row `LIMIT 1` returns on a tie — the admin could land
  # back on the stale published draw instead of the fresh draft. Widening
  # to microsecond precision makes same-timestamp collisions between two
  # real, sequential inserts effectively impossible.
  def change do
    alter table(:draws) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
