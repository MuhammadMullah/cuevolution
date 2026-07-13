defmodule Cuevolution.Accounts.ProfilePicture.Storage.S3 do
  @moduledoc """
  Production profile picture storage — uploads to a private AWS S3 bucket
  via `ex_aws`/`ex_aws_s3`, configured through `config :cuevolution, :s3`
  (`:bucket`) and `config :ex_aws` (credentials/region) — see
  config/runtime.exs.

  A Mix release's own priv/static lives inside the release's versioned
  directory, replaced wholesale on every deploy, so anything written there
  (the `Storage.Local` approach, used in dev/test) doesn't survive a
  redeploy — S3 is a real object store instead.

  The bucket is **private**: `url/1` returns a short-lived presigned GET
  URL rather than a permanent public one, generated fresh on every call.
  That's why `ProfilePicture.store/2` persists the object `key`, never a
  URL — a stored URL would eventually expire.
  """
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage

  alias Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester.Live

  @url_expires_in_seconds 3600

  @impl true
  def put(key, body, content_type) do
    bucket()
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> requester().request()
    |> normalize()
  end

  @impl true
  def url(key) do
    {:ok, url} =
      :s3
      |> ExAws.Config.new([])
      |> ExAws.S3.presigned_url(:get, bucket(), key, expires_in: @url_expires_in_seconds)

    url
  end

  # ExAws.request/1 already normalizes non-2xx into
  # {:error, {:http_error, status, body}} itself — {:ok, _} is always
  # success here.
  defp normalize({:ok, _response}), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}

  defp bucket, do: Application.fetch_env!(:cuevolution, :s3)[:bucket]

  defp requester, do: Application.get_env(:cuevolution, :s3_requester, Live)
end
