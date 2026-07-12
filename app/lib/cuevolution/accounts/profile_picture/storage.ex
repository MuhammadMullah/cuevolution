defmodule Cuevolution.Accounts.ProfilePicture.Storage do
  @moduledoc """
  Where a resized profile picture's bytes actually end up — swappable via
  `config :cuevolution, :profile_picture_storage` so `ProfilePicture` stays
  unaware of the concrete backend.

  `Local` (dev/test default) writes under this app's own priv/static, no
  credentials needed. `Backblaze` (production) uploads to a B2 bucket over
  its S3-compatible API — see `Storage.Backblaze` for why a Mix release's
  own priv/static is the wrong place for this in production.
  """

  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              {:ok, public_url :: String.t()} | {:error, term()}
end
