defmodule Cuevolution.Accounts.ProfilePicture.Storage.GCSTest do
  use ExUnit.Case, async: true

  import Mox

  alias Cuevolution.Accounts.ProfilePicture.Storage.GCS
  alias Cuevolution.Accounts.ProfilePicture.Storage.GCS.Requester.Mock

  setup :verify_on_exit!

  describe "put/3" do
    test "uploads the bytes to the configured bucket" do
      expect(Mock, :put, fn bucket, key, body, content_type ->
        assert bucket == "test-bucket"
        assert key == "players/avatar.jpg"
        assert body == "jpeg-bytes"
        assert content_type == "image/jpeg"
        :ok
      end)

      assert :ok = GCS.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
    end

    test "passes through upload failures" do
      expect(Mock, :put, fn _bucket, _key, _body, _content_type ->
        {:error, {:http_error, 403, "Forbidden"}}
      end)

      assert {:error, {:http_error, 403, "Forbidden"}} =
               GCS.put("players/avatar.jpg", "jpeg-bytes", "image/jpeg")
    end
  end

  describe "url/1" do
    test "returns a V4 signed GET URL" do
      expect(Mock, :sign, fn service_account, payload ->
        assert service_account == "cuevolution-web@test-project.iam.gserviceaccount.com"
        assert payload =~ "GOOG4-RSA-SHA256"
        {:ok, :crypto.strong_rand_bytes(256)}
      end)

      url = GCS.url("players/avatar.jpg")

      assert url =~ "https://storage.googleapis.com/test-bucket/players/avatar.jpg?"
      assert url =~ "X-Goog-Algorithm=GOOG4-RSA-SHA256"
      assert url =~ "X-Goog-Expires=3600"
      assert url =~ "X-Goog-Signature="
    end
  end
end
