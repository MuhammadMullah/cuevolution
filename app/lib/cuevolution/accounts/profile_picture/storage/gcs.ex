defmodule Cuevolution.Accounts.ProfilePicture.Storage.GCS do
  @moduledoc """
  Production profile-picture storage in a private Google Cloud Storage bucket.

  Objects are uploaded through the JSON API using the Cloud Run service account.
  Reads use V4 signed URLs; the signature is delegated to IAM Credentials so no
  service-account private key is stored in the application or Secret Manager.
  """
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage

  alias Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester.Live

  @url_expires_in_seconds 3600
  @storage_host "storage.googleapis.com"

  @impl true
  def put(key, body, content_type), do: requester().put(bucket(), key, body, content_type)

  @impl true
  def url(key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    timestamp = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date = Calendar.strftime(now, "%Y%m%d")
    credential = "#{signing_service_account()}/#{date}/auto/storage/goog4_request"

    query = %{
      "X-Goog-Algorithm" => "GOOG4-RSA-SHA256",
      "X-Goog-Credential" => credential,
      "X-Goog-Date" => timestamp,
      "X-Goog-Expires" => Integer.to_string(@url_expires_in_seconds),
      "X-Goog-SignedHeaders" => "host"
    }

    canonical_query = canonical_query(query)
    canonical_uri = "/#{bucket()}/#{encode_path(key)}"

    canonical_request =
      [
        "GET",
        canonical_uri,
        canonical_query,
        "host:#{@storage_host}",
        "",
        "host",
        "UNSIGNED-PAYLOAD"
      ]
      |> Enum.join("\n")

    string_to_sign =
      [
        "GOOG4-RSA-SHA256",
        timestamp,
        "#{date}/auto/storage/goog4_request",
        sha256(canonical_request)
      ]
      |> Enum.join("\n")

    {:ok, signature} = requester().sign(signing_service_account(), string_to_sign)

    "https://#{@storage_host}#{canonical_uri}?#{canonical_query}&X-Goog-Signature=#{Base.encode16(signature, case: :lower)}"
  end

  defp bucket, do: Application.fetch_env!(:cuevolution, :gcs)[:bucket]

  defp signing_service_account,
    do: Application.fetch_env!(:cuevolution, :gcs)[:signing_service_account]

  defp requester, do: Application.get_env(:cuevolution, :gcs_requester, Live)

  defp canonical_query(query) do
    query
    |> Enum.sort()
    |> Enum.map_join("&", fn {key, value} -> "#{encode(key)}=#{encode(value)}" end)
  end

  defp encode_path(value),
    do: value |> String.split("/", trim: false) |> Enum.map_join("/", &encode/1)

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
