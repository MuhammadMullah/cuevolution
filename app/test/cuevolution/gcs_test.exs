defmodule Cuevolution.GCSTest do
  use ExUnit.Case, async: true

  import Mox

  alias Cuevolution.GCS
  alias Cuevolution.GCS.Requester.Mock

  setup :verify_on_exit!

  describe "put/4" do
    test "uploads the bytes to the given bucket" do
      expect(Mock, :put, fn bucket, key, body, content_type ->
        assert bucket == "a-bucket"
        assert key == "sheets/venue_stage_2026-10-11.pdf"
        assert body == "pdf-bytes"
        assert content_type == "application/pdf"
        :ok
      end)

      assert :ok =
               GCS.put(
                 "a-bucket",
                 "sheets/venue_stage_2026-10-11.pdf",
                 "pdf-bytes",
                 "application/pdf"
               )
    end

    test "passes through upload failures" do
      expect(Mock, :put, fn _bucket, _key, _body, _content_type ->
        {:error, {:http_error, 403, "Forbidden"}}
      end)

      assert {:error, {:http_error, 403, "Forbidden"}} =
               GCS.put("a-bucket", "key", "body", "application/pdf")
    end
  end

  describe "url/3" do
    test "returns a V4 signed GET URL scoped to the given bucket and service account" do
      expect(Mock, :sign, fn service_account, payload ->
        assert service_account == "signer@test-project.iam.gserviceaccount.com"
        assert payload =~ "GOOG4-RSA-SHA256"
        {:ok, :crypto.strong_rand_bytes(256)}
      end)

      url =
        GCS.url(
          "a-bucket",
          "sheets/venue_stage_2026-10-11.pdf",
          "signer@test-project.iam.gserviceaccount.com"
        )

      assert url =~ "https://storage.googleapis.com/a-bucket/sheets/venue_stage_2026-10-11.pdf?"
      assert url =~ "X-Goog-Algorithm=GOOG4-RSA-SHA256"
      assert url =~ "X-Goog-Expires=3600"
      assert url =~ "X-Goog-Signature="
    end
  end
end
