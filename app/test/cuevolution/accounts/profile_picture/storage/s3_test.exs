defmodule Cuevolution.Accounts.ProfilePicture.Storage.S3Test do
  use ExUnit.Case, async: true

  import Mox

  alias Cuevolution.Accounts.ProfilePicture.Storage.S3
  alias Cuevolution.Accounts.ProfilePicture.Storage.S3.Requester.Mock

  setup :verify_on_exit!

  describe "put/3" do
    test "uploads the bytes, returning :ok on success" do
      expect(Mock, :request, fn %ExAws.Operation.S3{} = op ->
        assert op.http_method == :put
        assert op.bucket == "test-bucket"
        assert op.path == "players/avatar.jpg"
        assert op.body == "jpeg-bytes"
        assert op.headers["content-type"] == "image/jpeg"

        {:ok, %{status_code: 200}}
      end)

      assert :ok = S3.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
    end

    test "passes through the error unchanged on failure" do
      expect(Mock, :request, fn _op -> {:error, {:http_error, 403, "Forbidden"}} end)

      assert {:error, {:http_error, 403, "Forbidden"}} =
               S3.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
    end
  end

  describe "url/1" do
    test "returns a presigned GET URL for the configured bucket — pure local computation, no request seam involved" do
      url = S3.url("players/avatar.jpg")

      assert url =~ "test-bucket"
      assert url =~ "players/avatar.jpg"
      assert url =~ "X-Amz-Signature="
      assert url =~ "X-Amz-Expires=3600"
    end
  end
end
