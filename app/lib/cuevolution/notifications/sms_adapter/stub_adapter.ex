defmodule Cuevolution.Notifications.SmsAdapter.StubAdapter do
  @moduledoc """
  Stand-in SMS "provider" until a real one is chosen (spec 002 Assumptions
  — provider selection is deferred per scope doc §9). Never actually sends
  anything over the network; prints the message body to the console so a
  developer running `mix phx.server`/`iex -S mix` can see what would have
  gone out. Configured for `:dev` and `:prod` — `:test` instead configures
  `Cuevolution.Notifications.SmsAdapter.SmsAdapterMock` (see
  `test/support/mocks.ex`), which defaults to a silent `{:ok, _}` so test
  runs don't get spammed with console output.
  """
  @behaviour Cuevolution.Notifications.SmsAdapter

  @impl true
  def send(mobile_number, body) do
    IO.puts("[SMS stub] to: #{mobile_number}\n#{body}")
    {:ok, %{to: mobile_number, body: body}}
  end
end
