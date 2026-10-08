defmodule DebugScopeTest do
  use Cuevolution.DataCase, async: true
  alias Cuevolution.Competitions

  test "debug region scoping 4" do
    coordinator_region = Repo.get_by!(Cuevolution.Accounts.Region, name: "Central")
    other_region = Repo.get_by!(Cuevolution.Accounts.Region, name: "Eastern")
    coordinator = insert(:admin, role: "regional_coordinator", region_id: coordinator_region.id)
    other_venue = insert(:venue, region_id: other_region.id)
    fixture = insert(:fixture, venue_id: other_venue.id)

    unplayed = Competitions.list_unplayed_fixtures_for_admin(coordinator)
    IO.inspect(Enum.map(unplayed, & &1.id), label: "unplayed fixture ids visible to coordinator")
    IO.inspect(fixture.id, label: "the fixture we created (outside region)")
  end
end
