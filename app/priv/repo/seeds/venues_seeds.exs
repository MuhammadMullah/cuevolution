defmodule Cuevolution.Seeds.Venues do
  @moduledoc """
  Seeds a couple of venues per region. Idempotent — safe to re-run.
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue

  @venues_per_region 2

  def run do
    regions = Repo.all(Region)

    Enum.each(regions, fn region ->
      Enum.each(1..@venues_per_region, fn n ->
        name = "#{region.name} Hall #{n}"

        unless Repo.exists?(from v in Venue, where: v.region_id == ^region.id and v.name == ^name) do
          {:ok, _venue} = Venues.create_venue(%{name: name, region_id: region.id})
        end
      end)
    end)

    IO.puts("Seeded venues for #{length(regions)} regions.")
  end
end

Cuevolution.Seeds.Venues.run()
