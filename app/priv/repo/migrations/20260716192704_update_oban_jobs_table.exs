defmodule Cuevolution.Repo.Migrations.UpdateObanJobsTable do
  use Ecto.Migration

  @moduledoc """
  The original AddObanJobsTable migration only ran once, so bumping the
  oban dep afterward (2.23.0, schema v14 — see
  deps/oban/lib/oban/migrations/postgres.ex) never touched the DB. Oban's
  own migrator is incremental/idempotent: calling `up/1` again here brings
  an older schema forward (e.g. the `oban_peers` table added in v11)
  without re-running anything already applied.
  """

  def up, do: Oban.Migrations.up(version: 14)

  def down, do: Oban.Migrations.down(version: 11)
end
