defmodule Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester.Live do
  @moduledoc "Real `Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester` — delegates straight to `ExAws.request/1`."
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester

  @impl true
  def request(operation), do: ExAws.request(operation)
end
