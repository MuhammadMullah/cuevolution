defmodule Cuevolution.Seeds.Regions do
  @moduledoc """
  Seeds the fixed set of competition regions. Idempotent — safe to re-run.
  Must run before Venues/Accounts/Teams, which all reference a region.
  """

  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo

  @regions [
    "Nairobi A",
    "Nairobi B",
    "Central",
    "Eastern",
    "Coast",
    "Rift A",
    "Rift B",
    "Nyanza & Western"
  ]

  def run do
    existing_slugs = Repo.all(Region) |> MapSet.new(& &1.slug)

    inserted =
      @regions
      |> Enum.reject(&(slug(&1) in existing_slugs))
      |> Enum.map(fn name ->
        Repo.insert!(%Region{name: name, slug: slug(name)})
      end)

    IO.puts("Seeded #{length(inserted)} new region(s) (#{length(@regions)} total).")
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end

Cuevolution.Seeds.Regions.run()
