# Script for populating the database. Run it as:
#
#     mix run priv/repo/seeds.exs
#
# Each context's seed data lives in its own file under priv/repo/seeds/ and
# self-executes its `run/0` when loaded — that file is also independently
# runnable on its own, e.g. `mix run priv/repo/seeds/regions_seeds.exs`.
# Every `run/0` is idempotent, so loading a file twice (e.g. once directly,
# once via this script) is safe.
#
# Loaded in dependency order: Regions before Venues/Accounts (both reference
# a region), Venues before Accounts (players pick a venue at registration),
# Accounts before Teams (teams need players to captain them).

for file <- ~w(regions_seeds.exs venues_seeds.exs accounts_seeds.exs teams_seeds.exs) do
  Code.require_file(Path.join([__DIR__, "seeds", file]))
end
