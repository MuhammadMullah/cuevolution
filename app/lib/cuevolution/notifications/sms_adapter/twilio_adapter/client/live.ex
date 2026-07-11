defmodule Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client.Live do
  @moduledoc "Real `Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client` — delegates straight to `ExTwilio.Message.create/1`."
  @behaviour Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client

  @impl true
  def create(params), do: ExTwilio.Message.create(params)
end
