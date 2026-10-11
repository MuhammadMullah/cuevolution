defmodule Cuevolution.Competitions.ResultSheet.Storage do
  @moduledoc """
  Where an uploaded result sheet's bytes actually end up — swappable via
  `config :cuevolution, :result_sheet_storage`, same shape as
  `Cuevolution.Accounts.ProfilePicture.Storage`. `Local` (dev/test
  default) writes under this app's own priv/static; `GCS` (production)
  uploads to a private bucket and signs short-lived read URLs.
  """

  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @callback url(key :: String.t()) :: String.t()
end
