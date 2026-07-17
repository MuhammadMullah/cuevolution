defmodule Cuevolution.Seeds.Venues do
  @moduledoc """
  Seeds the real preloaded venue list per region (spec 004). Idempotent —
  safe to re-run; matches on (region, name) and only inserts what's missing.
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue

  @venues_by_region %{
    "Nairobi A" => [
      "Mchana Pool Club (Ngong Rd)",
      "Kapande Pool Club (Wilson)",
      "Jamlok Sport Bar (Sabaki)",
      "Mongolian (Rongai)",
      "Wallets (Utawala)"
    ],
    "Nairobi B" => [
      "Kasarani Pool Club (Kasarani)",
      "Magic Pool Club (Kasarani)",
      "Mahutini (Kariobangi)",
      "Eaglers (Kariobangi)",
      "Quiver Eastlands",
      "Sindicate (Mirema Drive)",
      "Jazlin (Ruai)"
    ],
    "Eastern" => [
      "Waves (Kitui)",
      "Rack City (Kitengela)"
    ],
    "Coast" => [
      "Kingston Beach Resort (Nyali)",
      "Mingles (Nyali)",
      "Masai Nyali",
      "Makuli (Makupa)",
      "Screenshot (Mtwapa)"
    ],
    "Nyanza & Western" => [
      "Canopy (Kisumu)",
      "Rack Attack (Kisumu)",
      "Berlin Lounge (Kisumu)",
      "Komeko (Kisumu)",
      "Wayside (Kisumu)",
      "Zero 7 (Kakamega)"
    ],
    "North Rift" => [
      "Tamasha Lounge (Eldoret)",
      "Lobo Village (Eldoret)",
      "Timber XO (Eldoret)",
      "Foxys",
      "Olympia",
      "Chill Spot"
    ],
    "South Rift" => [
      "Space Next Door",
      "Chillis",
      "Laikis (Narok)",
      "Tunnel (Litein)",
      "Mara Vegas (Narok)"
    ],
    "Central" => [
      "Aquatic (Meru)"
    ]
  }

  # Matches the generic placeholder venues ("Nairobi A Hall 1", etc.) this
  # file used to seed before the real per-region list above existed — never
  # matches a real venue name.
  @placeholder_name ~r/ Hall \d+$/

  def run do
    regions = Repo.all(Region)
    deactivated = deactivate_placeholders()
    inserted = Enum.flat_map(regions, &seed_region/1)

    IO.puts(
      "Seeded #{length(inserted)} new venue(s), deactivated #{length(deactivated)} " <>
        "placeholder venue(s), across #{length(regions)} region(s)."
    )
  end

  defp deactivate_placeholders do
    Venue
    |> where(active: true)
    |> Repo.all()
    |> Enum.filter(&Regex.match?(@placeholder_name, &1.name))
    |> Enum.map(fn venue ->
      {:ok, venue} = Venues.deactivate_venue(venue)
      venue
    end)
  end

  defp seed_region(region) do
    region.name
    |> then(&Map.get(@venues_by_region, &1, []))
    |> Enum.reject(&venue_exists?(region, &1))
    |> Enum.map(fn name ->
      {:ok, venue} = Venues.create_venue(%{name: name, region_id: region.id})
      venue
    end)
  end

  defp venue_exists?(region, name) do
    Repo.exists?(from v in Venue, where: v.region_id == ^region.id and v.name == ^name)
  end
end

Cuevolution.Seeds.Venues.run()
