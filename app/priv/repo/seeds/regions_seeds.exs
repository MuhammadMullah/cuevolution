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
    "North Rift",
    "South Rift",
    "Nyanza & Western"
  ]

  # "Rift A"/"Rift B" were placeholder names used before the real regional
  # names were known. Renamed in place (rather than left to insert as new
  # rows below) so any region already seeded/referenced under the old name
  # keeps its id — no orphaned duplicate and no dangling foreign keys on
  # players/venues that already point at it.
  @renames %{
    "Rift A" => "North Rift",
    "Rift B" => "South Rift"
  }

  def run do
    rename_existing()

    existing_slugs = Repo.all(Region) |> MapSet.new(& &1.slug)

    inserted =
      @regions
      |> Enum.reject(&(slug(&1) in existing_slugs))
      |> Enum.map(fn name ->
        Repo.insert!(%Region{name: name, slug: slug(name)})
      end)

    IO.puts("Seeded #{length(inserted)} new region(s) (#{length(@regions)} total).")
  end

  defp rename_existing do
    Enum.each(@renames, fn {old_name, new_name} ->
      case Repo.get_by(Region, slug: slug(old_name)) do
        nil ->
          :ok

        region ->
          region
          |> Ecto.Changeset.change(name: new_name, slug: slug(new_name))
          |> Repo.update!()
      end
    end)
  end

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end

Cuevolution.Seeds.Regions.run()
