defmodule Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester do
  @moduledoc """
  Seam around `ExAws.request/1` for the actual upload — `ex_aws` talks
  HTTP via `hackney` directly, with no pluggable test transport (unlike
  `Req`, which other adapters stub via `Req.Test`). Swapping this module
  via `config :cuevolution, :s3_requester` is what lets `Storage.S3`'s
  tests Mox-mock the network boundary.

  Not involved in `Storage.S3.url/1` — presigning a URL is pure local
  SigV4 computation, no HTTP call at all.
  """

  @callback request(ExAws.Operation.t()) :: {:ok, map()} | {:error, term()}
end
