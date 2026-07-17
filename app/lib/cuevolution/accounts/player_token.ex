defmodule Cuevolution.Accounts.PlayerToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @session_validity_in_days 60
  @reset_password_validity_in_minutes 20

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "player_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :player, Cuevolution.Accounts.Player

    timestamps(updated_at: false)
  end

  @doc "Builds an opaque token and its persistable session-context struct for the given player."
  def build_session_token(player) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", player_id: player.id}}
  end

  @doc """
  Returns a query that, given a session token, finds the player it belongs to
  (and only if the token hasn't expired).
  """
  def verify_session_token_query(token) do
    query =
      from t in by_token_and_context_query(token, "session"),
        join: player in assoc(t, :player),
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        select: player

    {:ok, query}
  end

  @doc """
  Builds a password-reset token: returns `{url_safe_raw_token, token_struct}`.

  Unlike the session token above, this one is emailed to the player, so only
  its hash is persisted — the raw value is never stored anywhere, matching
  `phx.gen.auth`'s approach to reset tokens (a DB read alone can't
  reconstruct a working reset link).
  """
  def build_reset_password_token(player) do
    raw = :crypto.strong_rand_bytes(@rand_size)

    token_struct = %__MODULE__{
      token: :crypto.hash(:sha256, raw),
      context: "reset_password",
      sent_to: player.email,
      player_id: player.id
    }

    {Base.url_encode64(raw, padding: false), token_struct}
  end

  @doc """
  Verifies an encoded reset-password token and returns a query resolving to
  its player, or `:error` if the string isn't even decodable — a malformed
  or never-issued token is treated identically to an expired one by the
  caller, so this doesn't need to distinguish the two.
  """
  def verify_reset_password_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, raw} ->
        hashed = :crypto.hash(:sha256, raw)

        query =
          from t in by_token_and_context_query(hashed, "reset_password"),
            join: player in assoc(t, :player),
            where: t.inserted_at > ago(@reset_password_validity_in_minutes, "minute"),
            select: player

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  def by_player_and_contexts_query(player, :all) do
    from t in __MODULE__, where: t.player_id == ^player.id
  end

  def by_player_and_contexts_query(player, [_ | _] = contexts) do
    from t in __MODULE__, where: t.player_id == ^player.id and t.context in ^contexts
  end
end
