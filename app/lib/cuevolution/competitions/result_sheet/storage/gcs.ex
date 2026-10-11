defmodule Cuevolution.Competitions.ResultSheet.Storage.GCS do
  @moduledoc """
  Production result-sheet storage in a private Google Cloud Storage bucket
  — a separate bucket from profile pictures, same VM service account.
  Thin adapter over `Cuevolution.GCS`.
  """
  @behaviour Cuevolution.Competitions.ResultSheet.Storage

  alias Cuevolution.GCS

  @impl true
  def put(key, body, content_type), do: GCS.put(bucket(), key, body, content_type)

  @impl true
  def url(key), do: GCS.url(bucket(), key, signing_service_account())

  defp bucket, do: Application.fetch_env!(:cuevolution, :gcs_result_sheets_bucket)

  defp signing_service_account,
    do: Application.fetch_env!(:cuevolution, :gcs)[:signing_service_account]
end
