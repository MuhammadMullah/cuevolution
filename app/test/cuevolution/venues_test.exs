defmodule Cuevolution.VenuesTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.Region
  alias Cuevolution.Venues

  defp region(slug) do
    Repo.get_by!(Region, slug: slug)
  end

  describe "list_active_for_region/1" do
    test "returns only the venues belonging to the given region (cross-region isolation)" do
      nairobi_a = region("nairobi-a")
      coast = region("coast")

      venue_a = insert(:venue, region_id: nairobi_a.id, name: "Nairobi A Venue")
      _venue_b = insert(:venue, region_id: coast.id, name: "Coast Venue")

      results = Venues.list_active_for_region(nairobi_a.id)

      assert [found] = results
      assert found.id == venue_a.id
    end

    test "excludes deactivated venues" do
      nairobi_a = region("nairobi-a")

      _active = insert(:venue, region_id: nairobi_a.id, name: "Active Venue")
      _inactive = insert(:venue, region_id: nairobi_a.id, name: "Inactive Venue", active: false)

      results = Venues.list_active_for_region(nairobi_a.id)

      assert length(results) == 1
      assert hd(results).name == "Active Venue"
    end

    test "returns an empty list for a region with no venues" do
      coast = region("coast")
      assert Venues.list_active_for_region(coast.id) == []
    end
  end

  describe "venue_name_taken_in_region?/2" do
    test "true for an exact, case-insensitive, trimmed match in the region" do
      nairobi_a = region("nairobi-a")
      insert(:venue, region_id: nairobi_a.id, name: "Cue Sports Pool")

      assert Venues.venue_name_taken_in_region?(nairobi_a.id, "cue sports pool")
      assert Venues.venue_name_taken_in_region?(nairobi_a.id, "  Cue Sports Pool  ")
    end

    test "false for a name that doesn't match any venue in the region" do
      nairobi_a = region("nairobi-a")
      insert(:venue, region_id: nairobi_a.id, name: "Cue Sports Pool")

      refute Venues.venue_name_taken_in_region?(nairobi_a.id, "Somewhere Else")
    end

    test "false for a match that only exists in a different region" do
      nairobi_a = region("nairobi-a")
      coast = region("coast")
      insert(:venue, region_id: coast.id, name: "Cue Sports Pool")

      refute Venues.venue_name_taken_in_region?(nairobi_a.id, "Cue Sports Pool")
    end

    test "false for a match that only exists on a deactivated venue" do
      nairobi_a = region("nairobi-a")
      insert(:venue, region_id: nairobi_a.id, name: "Cue Sports Pool", active: false)

      refute Venues.venue_name_taken_in_region?(nairobi_a.id, "Cue Sports Pool")
    end

    test "false for a blank name" do
      nairobi_a = region("nairobi-a")
      refute Venues.venue_name_taken_in_region?(nairobi_a.id, "")
      refute Venues.venue_name_taken_in_region?(nairobi_a.id, "   ")
    end
  end

  describe "list_venues/1" do
    test "returns every venue, including inactive ones, for the admin management view" do
      nairobi_a = region("nairobi-a")
      active = insert(:venue, region_id: nairobi_a.id, name: "Active")
      inactive = insert(:venue, region_id: nairobi_a.id, name: "Inactive", active: false)

      results = Venues.list_venues()

      ids = Enum.map(results, & &1.id)
      assert active.id in ids
      assert inactive.id in ids
    end

    test "filters by region_id when given" do
      nairobi_a = region("nairobi-a")
      coast = region("coast")
      venue_a = insert(:venue, region_id: nairobi_a.id)
      _venue_b = insert(:venue, region_id: coast.id)

      results = Venues.list_venues(%{region_id: nairobi_a.id})

      assert [found] = results
      assert found.id == venue_a.id
    end

    test "preloads region without N+1 queries" do
      insert_list(3, :venue)

      {queries, _result} = with_query_count(fn -> Venues.list_venues() end)
      assert queries == 2
    end
  end

  defp with_query_count(fun) do
    test_pid = self()
    counter = :counters.new(1, [])

    handler = fn _event, _measurements, _metadata, _config ->
      # Telemetry handlers are global — without this guard, queries from
      # other concurrently-running async tests would inflate this count.
      if self() == test_pid, do: :counters.add(counter, 1, 1)
    end

    handler_id = "venues-query-counter-test-#{inspect(test_pid)}"
    :telemetry.attach(handler_id, [:cuevolution, :repo, :query], handler, nil)
    result = fun.()
    :telemetry.detach(handler_id)

    {:counters.get(counter, 1), result}
  end

  describe "create_venue/1" do
    test "creates a venue with valid attrs" do
      nairobi_a = region("nairobi-a")

      assert {:ok, venue} =
               Venues.create_venue(%{name: "New Venue", region_id: nairobi_a.id})

      assert venue.name == "New Venue"
      assert venue.active == true
    end

    test "requires name and region_id" do
      assert {:error, changeset} = Venues.create_venue(%{})
      refute changeset.valid?
      assert errors_on(changeset)[:name]
      assert errors_on(changeset)[:region_id]
    end

    test "rejects a duplicate venue name within the same region, case-insensitively" do
      nairobi_a = region("nairobi-a")
      insert(:venue, region_id: nairobi_a.id, name: "Shared Name")

      assert {:error, changeset} =
               Venues.create_venue(%{name: "shared name", region_id: nairobi_a.id})

      assert "already exists in this region" in errors_on(changeset).name
    end

    test "allows the same venue name in a different region" do
      nairobi_a = region("nairobi-a")
      coast = region("coast")
      insert(:venue, region_id: nairobi_a.id, name: "Shared Name")

      assert {:ok, _venue} = Venues.create_venue(%{name: "Shared Name", region_id: coast.id})
    end

    test "allows re-creating a venue name that was previously deactivated" do
      nairobi_a = region("nairobi-a")
      insert(:venue, region_id: nairobi_a.id, name: "Old Venue", active: false)

      assert {:ok, _venue} = Venues.create_venue(%{name: "Old Venue", region_id: nairobi_a.id})
    end
  end

  describe "update_venue/2" do
    test "updates the venue's attributes" do
      venue = insert(:venue, name: "Original")

      assert {:ok, updated} = Venues.update_venue(venue, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "deactivate_venue/1" do
    test "soft-deletes the venue (active becomes false, row persists)" do
      venue = insert(:venue, active: true)

      assert {:ok, deactivated} = Venues.deactivate_venue(venue)
      assert deactivated.active == false
      assert Repo.get(Cuevolution.Venues.Venue, venue.id)
    end

    test "a deactivated venue disappears from the active listing but existing player references stay valid" do
      region = build(:region)
      venue = insert(:venue, region_id: region.id)
      player = insert(:player, region_id: region.id, preferred_venue_id: venue.id)

      assert {:ok, _} = Venues.deactivate_venue(venue)

      assert Venues.list_active_for_region(region.id) == []
      # The player's historical reference is untouched — no FK violation, no nullification.
      assert Repo.get!(Cuevolution.Accounts.Player, player.id).preferred_venue_id == venue.id
    end
  end
end
