defmodule Cuevolution.Accounts.AdminToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @session_validity_in_days 60

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
