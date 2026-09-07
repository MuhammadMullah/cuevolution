defmodule Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester do
  @moduledoc false

  @callback put(
              bucket :: String.t(),
              key :: String.t(),
              body :: binary(),
              content_type :: String.t()
            ) :: :ok | {:error, term()}

  @callback sign(
              service_account :: String.t(),
              payload :: binary()
            ) :: {:ok, binary()} | {:error, term()}
end
