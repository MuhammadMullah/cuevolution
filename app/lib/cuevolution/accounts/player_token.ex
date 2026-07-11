defmodule Cuevolution.Accounts.PlayerToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @session_validity_in_days 60

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
