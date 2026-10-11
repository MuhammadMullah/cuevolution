defmodule Cuevolution.Accounts.ProfilePicture.Storage.GCS do
  @moduledoc """
  Production profile-picture storage in a private Google Cloud Storage bucket.

  Thin adapter over `Cuevolution.GCS` — see that module for the actual
  upload/signing logic, shared with every other private bucket this app
  writes to.
  """
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage

  alias Cuevolution.GCS

  @impl true
  def put(key, body, content_type), do: GCS.put(bucket(), key, body, content_type)

  @impl true
  def url(key), do: GCS.url(bucket(), key, signing_service_account())

  defp bucket, do: Application.fetch_env!(:cuevolution, :gcs_profile_pictures_bucket)

  defp signing_service_account,
    do: Application.fetch_env!(:cuevolution, :gcs)[:signing_service_account]
end
