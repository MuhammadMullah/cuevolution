defmodule Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester.Live do
  @moduledoc false
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester

  @metadata_url "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
  @iam_url "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/"
  @storage_upload_url "https://storage.googleapis.com/upload/storage/v1/b/"

  @impl true
  def put(bucket, key, body, content_type) do
    url = @storage_upload_url <> URI.encode(bucket) <> "/o?uploadType=media&name=" <> encode(key)

    with {:ok, token} <- access_token(),
         {:ok, response} <-
           Req.post(url,
             body: body,
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", content_type}
             ],
             receive_timeout: 15_000
           ) do
      ensure_success(response)
    end
  end

  @impl true
  def sign(service_account, payload) do
    with {:ok, token} <- access_token(),
         {:ok, response} <-
           Req.post(@iam_url <> URI.encode(service_account) <> ":signBlob",
             headers: [{"authorization", "Bearer #{token}"}],
             json: %{payload: Base.encode64(payload)},
             receive_timeout: 15_000
           ),
         :ok <- ensure_success(response),
         signature when is_binary(signature) <- response.body["signedBlob"] do
      {:ok, Base.decode64!(signature)}
    else
      nil -> {:error, :missing_signed_blob}
      error -> error
    end
  end

  defp access_token do
    case Req.get(@metadata_url,
           headers: [{"metadata-flavor", "Google"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, response} -> {:error, {:metadata_token_failed, response.status, response.body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_success(%{status: status}) when status in 200..299, do: :ok
  defp ensure_success(%{status: status, body: body}), do: {:error, {:http_error, status, body}}

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
