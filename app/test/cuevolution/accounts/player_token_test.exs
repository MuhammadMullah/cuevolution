defmodule Cuevolution.Accounts.PlayerTokenTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts.PlayerToken
  alias Cuevolution.Repo

  describe "build_reset_password_token/1 and verify_reset_password_token_query/1" do
    test "round-trips: the encoded token resolves back to the player" do
      player = insert(:player)
      {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)
      Repo.insert!(token_struct)

      assert {:ok, query} = PlayerToken.verify_reset_password_token_query(encoded_token)
      assert Repo.one(query).id == player.id
    end

    test "the persisted token is hashed, not the raw emailed value (FR-009)" do
      player = insert(:player)
      {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)

      {:ok, raw} = Base.url_decode64(encoded_token, padding: false)
      refute token_struct.token == raw
      assert token_struct.token == :crypto.hash(:sha256, raw)
    end

    test "an expired token is rejected" do
      player = insert(:player)
      {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)

      token_struct
      |> Repo.insert!()
      |> Ecto.Changeset.change(inserted_at: seconds_ago(21 * 60))
      |> Repo.update!()

      assert {:ok, query} = PlayerToken.verify_reset_password_token_query(encoded_token)
      assert Repo.one(query) == nil
    end

    test "a malformed (non-base64) token string is rejected without crashing" do
      assert :error = PlayerToken.verify_reset_password_token_query("not a real token!")
    end

    test "a well-formed but never-issued token resolves to no player" do
      assert {:ok, query} = PlayerToken.verify_reset_password_token_query("not-a-real-token")
      assert Repo.one(query) == nil
    end

    test "a token issued for the session context doesn't verify as a reset token" do
      player = insert(:player)
      {session_token, _} = PlayerToken.build_session_token(player)
      encoded = Base.url_encode64(session_token, padding: false)

      assert {:ok, query} = PlayerToken.verify_reset_password_token_query(encoded)
      assert Repo.one(query) == nil
    end
  end

  defp seconds_ago(seconds) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-seconds, :second)
    |> NaiveDateTime.truncate(:second)
  end
end
