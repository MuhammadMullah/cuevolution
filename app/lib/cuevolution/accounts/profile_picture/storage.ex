defmodule Cuevolution.Accounts.ProfilePicture.Storage do
  @moduledoc """
  Where a resized profile picture's bytes actually end up — swappable via
  `config :cuevolution, :profile_picture_storage` so `ProfilePicture` stays
  unaware of the concrete backend.

  `Local` (dev/test default) writes under this app's own priv/static, no
  credentials needed. `S3` (production) uploads to a private AWS S3
  bucket — see `Storage.S3` for why a Mix release's own priv/static is the
  wrong place for this in production, and why the bucket is private
  (presigned URLs) rather than public.

  `put/3` stores the bytes under `key`. `url/1` turns that same `key` back
  into something a browser can actually load — a plain path for `Local`,
  a short-lived presigned URL for `S3`. Never persist the result of
  `url/1` — only the `key` (see `ProfilePicture.store/2`), since a
  presigned URL expires and a plain path doesn't survive a redeploy.
  """

  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @callback url(key :: String.t()) :: String.t()
end
