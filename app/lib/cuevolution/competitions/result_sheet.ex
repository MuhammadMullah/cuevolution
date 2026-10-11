defmodule Cuevolution.Competitions.ResultSheet do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @allowed_content_types ~w(image/jpeg application/pdf)

  @moduledoc """
  A scanned/photographed results sheet uploaded by an admin, kept for
  future reference rather than feeding standings (those still come from
  recorded `MatchResult`s). One row per venue/stage/day — re-uploading
  the same venue+stage on the same day replaces the prior sheet rather
  than piling up duplicates, matching the `venuename_stage_date` object
  key (see `Competitions.upload_result_sheet/5`), which is itself
  deterministic per venue/stage/day.
  """
  schema "result_sheets" do
    field :object_key, :string
    field :content_type, :string
    field :original_filename, :string
    field :uploaded_on, :date

    belongs_to :stage, Cuevolution.Competitions.Stage
    belongs_to :venue, Cuevolution.Venues.Venue
    belongs_to :uploaded_by_admin, Cuevolution.Accounts.Admin, foreign_key: :uploaded_by_admin_id

    timestamps()
  end

  def allowed_content_types, do: @allowed_content_types

  def changeset(result_sheet, attrs) do
    result_sheet
    |> cast(attrs, [
      :stage_id,
      :venue_id,
      :uploaded_by_admin_id,
      :object_key,
      :content_type,
      :original_filename,
      :uploaded_on
    ])
    |> validate_required([
      :stage_id,
      :venue_id,
      :uploaded_by_admin_id,
      :object_key,
      :content_type,
      :original_filename,
      :uploaded_on
    ])
    |> validate_inclusion(:content_type, @allowed_content_types)
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:uploaded_by_admin_id)
    |> unique_constraint([:venue_id, :stage_id, :uploaded_on], name: :result_sheets_unique_index)
  end
end
