defmodule Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client do
  @moduledoc """
  Seam around `ExTwilio.Message.create/1` — `ex_twilio` talks HTTP via
  `HTTPoison` directly (`use HTTPoison.Base` baked into `ExTwilio.Api`) with
  no pluggable test transport, unlike `Req` (see `AfricasTalkingAdapter`,
  which stubs `Req.Test` instead). Swapping this module via
  `config :cuevolution, :twilio_client` is what lets `TwilioAdapter`'s
  tests Mox-mock the network boundary.
  """

  @callback create(keyword) :: {:ok, struct()} | {:error, map(), integer()}
end
