defmodule Cuevolution.Accounts.AdminToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @session_validity_in_days 60
  @setup_validity_in_days 7

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :admin, Cuevolution.Accounts.Admin

    timestamps(updated_at: false)
  end

  @doc "Builds an opaque token and its persistable session-context struct for the given admin."
  def build_session_token(admin) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", admin_id: admin.id}}
  end

  @doc """
  Returns a query that, given a session token, finds the admin it belongs to
  (and only if the token hasn't expired).
  """
  def verify_session_token_query(token) do
    query =
      from t in by_token_and_context_query(token, "session"),
        join: admin in assoc(t, :admin),
        where: t.inserted_at > ago(@session_validity_in_days, "day"),
        select: admin

    {:ok, query}
  end

  @doc """
  Builds an account-setup token for a newly invited admin: returns
  `{url_safe_raw_token, token_struct}`. Only its hash is persisted, matching
  `PlayerToken.build_reset_password_token/1` — a DB read alone can't
  reconstruct a working setup link.
  """
  def build_admin_setup_token(admin) do
    raw = :crypto.strong_rand_bytes(@rand_size)

    token_struct = %__MODULE__{
      token: :crypto.hash(:sha256, raw),
      context: "admin_setup",
      sent_to: admin.email,
      admin_id: admin.id
    }

    {Base.url_encode64(raw, padding: false), token_struct}
  end

  @doc """
  Verifies an encoded account-setup token and returns a query resolving to
  its admin, or `:error` if the string isn't even decodable — a malformed
  or never-issued token is treated identically to an expired one by the
  caller.
  """
  def verify_admin_setup_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, raw} ->
        hashed = :crypto.hash(:sha256, raw)

        query =
          from t in by_token_and_context_query(hashed, "admin_setup"),
            join: admin in assoc(t, :admin),
            where: t.inserted_at > ago(@setup_validity_in_days, "day"),
            select: admin

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  def by_admin_and_contexts_query(admin, :all) do
    from t in __MODULE__, where: t.admin_id == ^admin.id
  end

  def by_admin_and_contexts_query(admin, [_ | _] = contexts) do
    from t in __MODULE__, where: t.admin_id == ^admin.id and t.context in ^contexts
  end
end
