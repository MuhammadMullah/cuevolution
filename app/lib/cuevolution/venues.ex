defmodule Cuevolution.Venues do
  @moduledoc """
  The Venues context: preloaded per-region venue lists (spec 004).
  """

  import Ecto.Query

  alias Cuevolution.Competitions
  alias Cuevolution.Repo
  alias Cuevolution.Venues.Venue
  alias Cuevolution.Venues.VenueDeactivationSuggestion
  alias Ecto.Multi

  @doc "Active venues for a region — the hot query behind registration's venue picker."
  def list_active_for_region(region_id) do
    Venue
    |> where(region_id: ^region_id, active: true)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Whether an active venue named `name` already exists in `region_id`,
  case-insensitive and whitespace-trimmed — used to stop registration's
  free-text "Other" venue from creating a duplicate of a venue that's
  already on the list (spec 004: a region shouldn't end up with both a real
  `Venue` row and a player's `other_venue_name` naming the same place).
  """
  def venue_name_taken_in_region?(region_id, name)
      when is_binary(region_id) and is_binary(name) do
    name = name |> String.trim() |> String.downcase()

    name != "" and
      Repo.exists?(
        from v in Venue,
          where: v.region_id == ^region_id and v.active,
          where: fragment("lower(trim(?))", v.name) == ^name
      )
  end

  def venue_name_taken_in_region?(_region_id, _name), do: false

  @doc """
  All venues, optionally filtered by `:region_id` and/or `:active`, for the
  admin management view.
  """
  def list_venues(filters \\ %{}) do
    Venue
    |> filter_by_region(filters[:region_id])
    |> filter_by_active(filters[:active])
    |> order_by(asc: :name)
    |> preload(:region)
    |> Repo.all()
  end

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  defp filter_by_active(query, nil), do: query
  defp filter_by_active(query, active), do: where(query, active: ^active)

  @doc "Fetches a venue by id, preloaded with its region — raises if not found."
  def get_venue!(id) do
    Venue
    |> preload(:region)
    |> Repo.get!(id)
  end

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

  Returns `{:error, :draws_exist}` if the venue already has fixtures or Grassroots
  draws.

  Otherwise, the venue is deactivated and its replacement venue suggestions are
  saved for affected players. Any previous suggestions are replaced.

  """
  def deactivate_venue(%Venue{} = venue, suggested_venue_ids \\ []) do
    if Competitions.venue_has_draws?(venue.id) do
      {:error, :draws_exist}
    else
      suggested_venue_ids =
        suggested_venue_ids
        |> Enum.reject(&(&1 == venue.id))
        |> Enum.uniq()

      Multi.new()
      |> Multi.update(:venue, Venue.changeset(venue, %{active: false}))
      |> Multi.delete_all(:clear_suggestions, suggestions_query(venue.id))
      |> Multi.run(:insert_suggestions, fn repo, _changes ->
        {:ok, insert_suggestions(repo, venue.id, suggested_venue_ids)}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{venue: venue}} -> {:ok, venue}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Reactivates a venue and clears any replacement venue suggestions saved during
  its previous deactivation.
  """
  def activate_venue(%Venue{} = venue) do
    Multi.new()
    |> Multi.update(:venue, Venue.changeset(venue, %{active: true}))
    |> Multi.delete_all(:clear_suggestions, suggestions_query(venue.id))
    |> Repo.transaction()
    |> case do
      {:ok, %{venue: venue}} -> {:ok, venue}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Active venues suggested as replacements when `venue_id` was deactivated —
  what a player whose `preferred_venue` was deactivated should be prompted
  with. A suggested venue that has since itself been deactivated is
  excluded.
  """
  def list_suggestions_for_venue(venue_id) do
    VenueDeactivationSuggestion
    |> where([s], s.venue_id == ^venue_id)
    |> join(:inner, [s], v in Venue, on: v.id == s.suggested_venue_id and v.active)
    |> select([s, v], v)
    |> order_by([s, v], asc: v.name)
    |> Repo.all()
  end

  @doc """
  Active venues in `region_id` other than `exclude_venue_id` — the options
  offered to an admin picking replacement suggestions while deactivating
  `exclude_venue_id`.
  """
  def list_active_venues_in_region(region_id, exclude_venue_id) do
    Venue
    |> where([v], v.region_id == ^region_id and v.active and v.id != ^exclude_venue_id)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp suggestions_query(venue_id) do
    from s in VenueDeactivationSuggestion, where: s.venue_id == ^venue_id
  end

  defp insert_suggestions(repo, venue_id, suggested_venue_ids) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(suggested_venue_ids, fn suggested_id ->
        %{
          id: Ecto.UUID.generate(),
          venue_id: venue_id,
          suggested_venue_id: suggested_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = repo.insert_all(VenueDeactivationSuggestion, rows)
    count
  end
end
