defmodule Cuevolution.Venues.VenueDeactivationSuggestion do
  @moduledoc """
  Records that `suggested_venue` was offered as a replacement when `venue`
  was deactivated — read back to prompt affected players (whose
  `preferred_venue_id` still points at `venue`) toward an active venue,
  and to build the `venue_deactivated` notification payload. Written via
  `Repo.insert_all`/deleted in bulk by `Venues.deactivate_venue/2` and
  `Venues.activate_venue/1`, not through a form changeset.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "venue_deactivation_suggestions" do
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :suggested_venue, Cuevolution.Venues.Venue

    timestamps()
  end
end
