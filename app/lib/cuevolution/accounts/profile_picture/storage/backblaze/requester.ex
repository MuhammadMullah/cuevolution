defmodule Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester do
  @moduledoc """
  Seam around `ExAws.request/1` — `ex_aws` talks HTTP via `hackney`
  directly, with no pluggable test transport (unlike `Req`, which
  `AfricasTalkingAdapter` stubs via `Req.Test`). Swapping this module via
  `config :cuevolution, :backblaze_requester` is what lets
  `Storage.Backblaze`'s tests Mox-mock the network boundary.
  """

  @callback request(ExAws.Operation.t()) :: {:ok, map()} | {:error, term()}
end
