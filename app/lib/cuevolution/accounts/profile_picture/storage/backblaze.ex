defmodule Cuevolution.Accounts.ProfilePicture.Storage.Backblaze do
  @moduledoc """
  Production profile picture storage — uploads to a Backblaze B2 bucket via
  its S3-compatible API (`ex_aws`/`ex_aws_s3`), configured through
  `config :cuevolution, :backblaze` (`:bucket`/`:host`) and `config :ex_aws`
  (credentials) — see config/runtime.exs.

  A Mix release's own priv/static lives inside the release's versioned
  directory, replaced wholesale on every deploy, so anything written there
  (the `Storage.Local` approach, used in dev/test) doesn't survive a
  redeploy — B2 is a real object store instead.

  The bucket is expected to be public (profile pictures aren't sensitive)
  so the returned URL is a plain public one, not a signed/expiring URL.
  """
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage

  alias Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester.Live

  @impl true
  def put(key, body, content_type) do
    bucket = config()[:bucket]

    bucket
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> requester().request()
    |> normalize(key)
  end

  # ExAws.request/1 already normalizes non-2xx into
  # {:error, {:http_error, status, body}} itself — {:ok, _} is always
  # success here.
  defp normalize({:ok, _response}, key), do: {:ok, public_url(key)}
  defp normalize({:error, reason}, _key), do: {:error, reason}

  defp public_url(key), do: "https://#{config()[:bucket]}.#{config()[:host]}/#{key}"

  defp config, do: Application.fetch_env!(:cuevolution, :backblaze)

  defp requester, do: Application.get_env(:cuevolution, :backblaze_requester, Live)
end
