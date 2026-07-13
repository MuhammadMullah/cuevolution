defmodule Cuevolution.Venues do
  @moduledoc """
  The Venues context: preloaded per-region venue lists (spec 004).
  """

  import Ecto.Query

  alias Cuevolution.Repo
  alias Cuevolution.Venues.Venue

  @doc "Active venues for a region — the hot query behind registration's venue picker."
  def list_active_for_region(region_id) do
    Venue
    |> where(region_id: ^region_id, active: true)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  All venues (active and inactive), optionally filtered by `:region_id`, for
  the admin management view.
  """
  def list_venues(filters \\ %{}) do
    Venue
    |> filter_by_region(filters[:region_id])
    |> order_by(asc: :name)
    |> preload(:region)
    |> Repo.all()
  end

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  @doc "Creates a venue (spec 004 FR-001)."
  def create_venue(attrs) do
    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a venue's attributes (spec 004 FR-001)."
  def update_venue(%Venue{} = venue, attrs) do
    venue
    |> Venue.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a venue (spec 004 FR-004): it drops out of active listings but
  the row (and any historical player references to it) stays intact.
  """
  def deactivate_venue(%Venue{} = venue) do
    venue
    |> Venue.changeset(%{active: false})
    |> Repo.update()
  end

  @doc "Reverses `deactivate_venue/1` — brings a venue back into active listings."
  def activate_venue(%Venue{} = venue) do
    venue
    |> Venue.changeset(%{active: true})
    |> Repo.update()
  end
end
