defmodule Cuevolution.Notifications.SmsAdapter.TwilioAdapterTest do
  # async: false — two tests below mutate the global :ex_twilio /
  # :cuevolution, :twilio Application env that every test in this file reads.
  use ExUnit.Case, async: false

  import Mox

  alias Cuevolution.Notifications.SmsAdapter.TwilioAdapter
  alias Cuevolution.Notifications.SmsAdapter.TwilioAdapter.Client.Mock

  setup :verify_on_exit!

  test "returns {:ok, message} for a successful send" do
    expect(Mock, :create, fn params ->
      assert params[:to] == "+254712345678"
      assert params[:from] == "+15005550006"
      assert params[:body] == "Hello from Cuevolution"

      {:ok, %ExTwilio.Message{sid: "SM123", status: "queued", to: params[:to]}}
    end)

    assert {:ok, %ExTwilio.Message{sid: "SM123", status: "queued"}} =
             TwilioAdapter.send("+254712345678", "Hello from Cuevolution")
  end

  test "returns {:error, {:http_error, status, body}} when Twilio rejects the request" do
    expect(Mock, :create, fn _params ->
      {:error, %{"message" => "The 'To' number is not a valid phone number.", "code" => 21_211},
       400}
    end)

    assert {:error, {:http_error, 400, %{"code" => 21_211}}} =
             TwilioAdapter.send("+254712345678", "Hi")
  end

  test "returns {:error, {:transport_error, reason}} for a transport-level failure" do
    expect(Mock, :create, fn _params -> raise HTTPoison.Error, reason: :timeout end)

    assert {:error, {:transport_error, :timeout}} = TwilioAdapter.send("+254712345678", "Hi")
  end

  test "fails clearly instead of sending when account_sid/auth_token aren't configured" do
    original = Application.get_env(:ex_twilio, :account_sid)
    Application.put_env(:ex_twilio, :account_sid, nil)
    on_exit(fn -> Application.put_env(:ex_twilio, :account_sid, original) end)

    expect(Mock, :create, 0, fn _params -> {:ok, %ExTwilio.Message{}} end)

    assert {:error, :missing_twilio_credentials} = TwilioAdapter.send("+254712345678", "Hi")
  end

  test "fails clearly instead of sending when the :from number isn't configured" do
    original = Application.get_env(:cuevolution, :twilio)
    Application.put_env(:cuevolution, :twilio, from: nil)
    on_exit(fn -> Application.put_env(:cuevolution, :twilio, original) end)

    expect(Mock, :create, 0, fn _params -> {:ok, %ExTwilio.Message{}} end)

    assert {:error, :missing_twilio_from_number} = TwilioAdapter.send("+254712345678", "Hi")
  end
end
