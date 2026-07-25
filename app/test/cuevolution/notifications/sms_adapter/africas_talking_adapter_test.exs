defmodule Cuevolution.Notifications.SmsAdapter.AfricasTalkingAdapterTest do
  # async: false — one test below mutates the global :africastalking
  # Application env, which every test in this file reads.
  use ExUnit.Case, async: false

  alias Cuevolution.Notifications.SmsAdapter.AfricasTalkingAdapter

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "returns {:ok, body} for a successful send (statusCode 101)" do
    Req.Test.stub(AfricasTalkingAdapter, fn conn ->
      assert conn.host == "api.sandbox.africastalking.com"
      assert conn.request_path == "/version1/messaging"
      assert Plug.Conn.get_req_header(conn, "apikey") == ["test_api_key"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      assert params["to"] == "+254712345678"
      assert params["message"] == "Hello from Cuevolution"
      assert params["username"] == "sandbox"
      assert params["from"] == "CUEVO"

      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Message" => "Sent to 1/1",
          "Recipients" => [
            %{
              "statusCode" => 101,
              "number" => "+254712345678",
              "status" => "Success",
              "cost" => "KES 0.8000",
              "messageId" => "ATXid_test"
            }
          ]
        }
      })
    end)

    assert {:ok, body} = AfricasTalkingAdapter.send("+254712345678", "Hello from Cuevolution")
    assert get_in(body, ["SMSMessageData", "Recipients", Access.at(0), "status"]) == "Success"
  end

  test "returns {:error, {:provider_rejected, status}} when Africa's Talking rejects the number" do
    Req.Test.stub(AfricasTalkingAdapter, fn conn ->
      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Message" => "Sent to 0/1",
          "Recipients" => [
            %{"statusCode" => 403, "number" => "+254700000000", "status" => "InvalidPhoneNumber"}
          ]
        }
      })
    end)

    assert {:error, {:provider_rejected, "InvalidPhoneNumber"}} =
             AfricasTalkingAdapter.send("+254700000000", "Hi")
  end

  test "returns {:error, {:http_error, status, body}} for a non-2xx HTTP response" do
    Req.Test.stub(AfricasTalkingAdapter, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "invalid api key"})
    end)

    assert {:error, {:http_error, 401, %{"error" => "invalid api key"}}} =
             AfricasTalkingAdapter.send("+254712345678", "Hi")
  end

  test "returns {:error, reason} for a transport-level failure" do
    Req.Test.stub(AfricasTalkingAdapter, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %Req.TransportError{reason: :timeout}} =
             AfricasTalkingAdapter.send("+254712345678", "Hi")
  end

  test "fails clearly instead of sending when credentials aren't configured" do
    original = Application.get_env(:cuevolution, :africastalking)
    Application.put_env(:cuevolution, :africastalking, username: "sandbox", api_key: nil)

    on_exit(fn -> Application.put_env(:cuevolution, :africastalking, original) end)

    assert {:error, :missing_africastalking_credentials} =
             AfricasTalkingAdapter.send("+254712345678", "Hi")
  end

  test "omits the sender id instead of sending from=\"\" when it's blank (e.g. an unset docker-compose env var)" do
    original = Application.get_env(:cuevolution, :africastalking)

    Application.put_env(:cuevolution, :africastalking,
      username: "sandbox",
      api_key: "test_api_key",
      sender_id: ""
    )

    on_exit(fn -> Application.put_env(:cuevolution, :africastalking, original) end)

    Req.Test.stub(AfricasTalkingAdapter, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)
      refute Map.has_key?(params, "from")

      Req.Test.json(conn, %{
        "SMSMessageData" => %{
          "Recipients" => [%{"statusCode" => 101, "status" => "Success"}]
        }
      })
    end)

    assert {:ok, _body} = AfricasTalkingAdapter.send("+254712345678", "Hi")
  end
end
