defmodule Cuevolution.Accounts.ProfilePicture.Storage.BackblazeTest do
  use ExUnit.Case, async: true

  import Mox

  alias Cuevolution.Accounts.ProfilePicture.Storage.Backblaze
  alias Cuevolution.Accounts.ProfilePicture.Storage.Backblaze.Requester.Mock

  setup :verify_on_exit!

  test "uploads the bytes and returns the bucket's public URL on success" do
    expect(Mock, :request, fn %ExAws.Operation.S3{} = op ->
      assert op.http_method == :put
      assert op.bucket == "test-bucket"
      assert op.path == "players/avatar.jpg"
      assert op.body == "jpeg-bytes"
      assert op.headers["content-type"] == "image/jpeg"

      {:ok, %{status_code: 200}}
    end)

    assert {:ok, "https://test-bucket.s3.us-west-004.backblazeb2.com/players/avatar.jpg"} =
             Backblaze.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
  end

  test "passes through the error unchanged on failure" do
    expect(Mock, :request, fn _op -> {:error, {:http_error, 403, "Forbidden"}} end)

    assert {:error, {:http_error, 403, "Forbidden"}} =
             Backblaze.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
  end
end
