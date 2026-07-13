defmodule Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester.Live do
  @moduledoc "Real `Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester` — delegates straight to `ExAws.request/1`."
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester

  @impl true
  def request(operation), do: ExAws.request(operation)
end
