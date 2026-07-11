defmodule Cuevolution.Notifications.SmsAdapter do
  @moduledoc """
  The contract any SMS provider integration must implement (spec 002
  FR-004/NFR-7.1). Callers (the Oban worker) only ever go through the
  module configured at `config :cuevolution, :sms_adapter` — never a
  concrete provider SDK — so the real provider can be swapped in later
  without touching dispatch/worker code.
  """

  @callback send(mobile_number :: String.t(), body :: String.t()) ::
              {:ok, term()} | {:error, term()}
end
