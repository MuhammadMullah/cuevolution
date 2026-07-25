defmodule Cuevolution.Notifications.SmsAdapter.AfricasTalkingAdapter do
  @moduledoc """
  Real Africa's Talking SMS integration (spec 002 FR-004) — implements
  `Cuevolution.Notifications.SmsAdapter` so the rest of the app (dispatch,
  the Oban worker) stays unaware of the concrete provider; only this
  module knows about Africa's Talking's request/response shape.

  Configured via `config :cuevolution, :africastalking` — see
  config/runtime.exs (production, live API) and config/dev.exs (Africa's
  Talking's free Sandbox app, for real end-to-end testing against
  whitelisted test numbers). `:username` decides which host is hit:
  Sandbox apps are always named "sandbox".
  """
  @behaviour Cuevolution.Notifications.SmsAdapter

  @live_url "https://api.africastalking.com/version1/messaging"
  @sandbox_url "https://api.sandbox.africastalking.com/version1/messaging"

  # https://developers.africastalking.com — statusCode 100/101/102 mean
  # Processed/Sent/Queued respectively; anything else (401 RiskHold, 402
  # InvalidSenderId, 403 InvalidPhoneNumber, etc.) is a rejection.
  @success_status_codes [100, 101, 102]

  @impl true
  def send(mobile_number, body) do
    config = Application.get_env(:cuevolution, :africastalking, [])
    username = config[:username]
    api_key = config[:api_key]

    if is_nil(username) or is_nil(api_key) do
      {:error, :missing_africastalking_credentials}
    else
      params =
        %{username: username, to: mobile_number, message: body}
        |> maybe_put_sender_id(config[:sender_id])

      request(url_for(username), api_key, params)
    end
  end

  defp url_for("sandbox"), do: @sandbox_url
  defp url_for(_username), do: @live_url

  defp maybe_put_sender_id(params, nil), do: params
  defp maybe_put_sender_id(params, ""), do: params
  defp maybe_put_sender_id(params, sender_id), do: Map.put(params, :from, sender_id)

  defp request(url, api_key, params) do
    req_options = Application.get_env(:cuevolution, :africastalking_req_options, [])

    opts =
      Keyword.merge(req_options,
        form: params,
        headers: [{"apiKey", api_key}, {"accept", "application/json"}]
      )

    url
    |> Req.post(opts)
    |> handle_transport_result()
  end

  defp handle_transport_result({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    handle_response_body(body)
  end

  defp handle_transport_result({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_transport_result({:error, reason}), do: {:error, reason}

  defp handle_response_body(%{"SMSMessageData" => %{"Recipients" => [recipient | _]}} = body) do
    if recipient["statusCode"] in @success_status_codes do
      {:ok, body}
    else
      {:error, {:provider_rejected, recipient["status"] || recipient["statusCode"]}}
    end
  end

  defp handle_response_body(body), do: {:error, {:unexpected_response, body}}
end
