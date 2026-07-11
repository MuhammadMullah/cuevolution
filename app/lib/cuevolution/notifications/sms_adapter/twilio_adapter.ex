defmodule Cuevolution.Notifications.SmsAdapter.TwilioAdapter do
  @moduledoc """
  Real Twilio SMS integration — implements `Cuevolution.Notifications.SmsAdapter`
  via the `ex_twilio` client library, so the rest of the app (dispatch, the
  Oban worker) stays unaware of the concrete provider.

  Configured via `config :ex_twilio, account_sid: ..., auth_token: ...`
  (ex_twilio's own config — see config/runtime.exs for production) plus
  `config :cuevolution, :twilio, from: "+1..."` for the Twilio number
  messages are sent from.

  `ex_twilio` talks HTTP via `HTTPoison` directly, with no pluggable test
  transport (unlike `Req`, which `AfricasTalkingAdapter` stubs via
  `Req.Test`). So the actual `ExTwilio.Message.create/1` call goes through
  the swappable `Client` behaviour (`config :cuevolution, :twilio_client`)
  instead of being called here directly — that's the seam tests Mox-mock.
  """
  @behaviour Cuevolution.Notifications.SmsAdapter

  alias Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client.Live

  @impl true
  def send(mobile_number, body) do
    case config_error() do
      nil -> do_send(mobile_number, body)
      reason -> {:error, reason}
    end
  end

  defp config_error do
    cond do
      is_nil(ExTwilio.Config.account_sid()) or is_nil(ExTwilio.Config.auth_token()) ->
        :missing_twilio_credentials

      is_nil(from_number()) ->
        :missing_twilio_from_number

      true ->
        nil
    end
  end

  defp from_number, do: Application.get_env(:cuevolution, :twilio, [])[:from]

  defp do_send(mobile_number, body) do
    [to: mobile_number, from: from_number(), body: body]
    |> client().create()
    |> normalize()
  rescue
    error in HTTPoison.Error -> {:error, {:transport_error, error.reason}}
  end

  defp client, do: Application.get_env(:cuevolution, :twilio_client, Live)

  defp normalize({:ok, message}), do: {:ok, message}
  defp normalize({:error, error_body, status}), do: {:error, {:http_error, status, error_body}}
end
