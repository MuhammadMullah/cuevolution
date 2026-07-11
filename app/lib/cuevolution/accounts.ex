defmodule Cuevolution.Accounts do
  @moduledoc """
  The Accounts context: admins, players, and regions.
  """

  import Ecto.Query

  require Logger

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.AdminActionLog
  alias Cuevolution.Accounts.AdminToken
  alias Cuevolution.Accounts.PhoneNumber
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.PlayerToken
  alias Cuevolution.Notifications
  alias Cuevolution.Repo

  @doc """
  Authenticates an admin by email and password.

  Always runs a bcrypt comparison (against a dummy hash when the email
  doesn't match anyone) so a non-existent email takes the same time as a
  wrong password — the caller can't distinguish the two failure modes.
  """
  def authenticate_admin(email, password) when is_binary(email) and is_binary(password) do
    admin = Repo.get_by(Admin, email: email)

    cond do
      admin && Bcrypt.verify_pass(password, admin.hashed_password) ->
        {:ok, admin}

      admin ->
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc "Generates a new session token for the admin and persists it."
  def generate_admin_session_token(admin) do
    {token, admin_token} = AdminToken.build_session_token(admin)
    Repo.insert!(admin_token)
    token
  end

  @doc "Looks up the admin for a given session token, or nil if it doesn't resolve to one."
  def get_admin_by_session_token(token) do
    {:ok, query} = AdminToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes an admin session token, invalidating it."
  def delete_admin_session_token(token) do
    Repo.delete_all(AdminToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  Records an admin action for the audit log (spec 001 FR-005).

  `entity` is the struct the action was performed on/against; its module
  name becomes `entity_type` and its `:id` becomes `entity_id`. First-time
  entries leave `:prior_value`/`:new_value` nil; corrections pass both.
  """
  def log_admin_action(action_type, %Admin{} = admin, entity, opts \\ []) do
    %AdminActionLog{}
    |> AdminActionLog.changeset(%{
      admin_id: admin.id,
      action_type: action_type,
      entity_type: entity.__struct__ |> to_string() |> String.trim_leading("Elixir."),
      entity_id: entity.id,
      prior_value: Keyword.get(opts, :prior_value),
      new_value: Keyword.get(opts, :new_value)
    })
    |> Repo.insert()
  end

  @doc """
  Whether `username` is already registered (case-insensitive) — used for
  live "is this available" feedback during registration. Not a substitute
  for the DB-backed unique constraint that actually guarantees correctness
  under concurrency (see `Player.registration_changeset/2`).
  """
  def username_taken?(""), do: false

  def username_taken?(username) when is_binary(username) do
    username = String.downcase(username)
    Repo.exists?(from p in Player, where: fragment("lower(?)", p.username) == ^username)
  end

  @doc """
  Whether `email` is already registered (case-insensitive) — same live-hint
  purpose and same caveat as `username_taken?/1`.
  """
  def email_taken?(""), do: false

  def email_taken?(email) when is_binary(email) do
    email = String.downcase(email)
    Repo.exists?(from p in Player, where: fragment("lower(?)", p.email) == ^email)
  end

  @doc """
  Whether `mobile_number` is already registered. Normalizes to E.164 first
  (same as `Player.registration_changeset/2`) so "0712345678" correctly
  matches a stored "+254712345678" — returns false if it doesn't normalize
  to a valid number at all. Same live-hint purpose and caveat as
  `username_taken?/1`.
  """
  def mobile_number_taken?(""), do: false

  def mobile_number_taken?(mobile_number) when is_binary(mobile_number) do
    case PhoneNumber.normalize(mobile_number) do
      {:ok, e164} -> Repo.exists?(from p in Player, where: p.mobile_number == ^e164)
      :error -> false
    end
  end

  @doc """
  Registers a player (spec 003 US1) and dispatches a registration-confirmation
  notification. A notification-dispatch failure is caught and logged — it
  never rolls back the already-committed account (spec 002).
  """
  def register_player(attrs) do
    case Player.registration_changeset(%Player{}, attrs) |> Repo.insert() do
      {:ok, player} ->
        dispatch_registration_confirmation(player)
        {:ok, player}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Authenticates a player by email-or-username and password.

  Mirrors `authenticate_admin/2`: same generic-error/dummy-hash behavior,
  entirely separate table and session from admin auth.
  """
  def authenticate_player(login, password) when is_binary(login) and is_binary(password) do
    player = Repo.one(player_by_login_query(login))

    cond do
      player && Bcrypt.verify_pass(password, player.hashed_password) ->
        {:ok, player}

      player ->
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  defp player_by_login_query(login) do
    login = String.downcase(login)

    from p in Player,
      where: fragment("lower(?)", p.email) == ^login or fragment("lower(?)", p.username) == ^login
  end

  @doc "Generates a new session token for the player and persists it."
  def generate_player_session_token(player) do
    {token, player_token} = PlayerToken.build_session_token(player)
    Repo.insert!(player_token)
    token
  end

  @doc "Looks up the player for a given session token, or nil if it doesn't resolve to one."
  def get_player_by_session_token(token) do
    {:ok, query} = PlayerToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes a player session token, invalidating it."
  def delete_player_session_token(token) do
    Repo.delete_all(PlayerToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc "Updates a player's notification preference (spec 003 US2)."
  def update_notification_preference(%Player{} = player, preference) do
    player
    |> Player.notification_preference_changeset(%{notification_preference: preference})
    |> Repo.update()
  end

  @doc """
  Filterable, index-backed player directory query (spec 010 US1).

  Supported filters: `:region_id`, `:category` (gender), `:username`
  (case-insensitive substring search). A `:stage` filter isn't implemented
  yet — it depends on `Competitions.StageParticipation`, which doesn't
  exist until Context 5 is built (mirrors the T027/T028/T032 deferral).
  """
  def list_players_filtered(filters) do
    Player
    |> filter_by_region(filters[:region_id])
    |> filter_by_category(filters[:category])
    |> filter_by_username(filters[:username])
    |> order_by(asc: :username)
    |> preload(:region)
    |> Repo.all()
  end

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, category), do: where(query, gender: ^category)

  defp filter_by_username(query, nil), do: query

  defp filter_by_username(query, username) do
    pattern = "%" <> String.replace(username, ~w(% _), fn c -> "\\" <> c end) <> "%"
    where(query, [p], ilike(p.username, ^pattern))
  end

  defp dispatch_registration_confirmation(player) do
    Notifications.dispatch(player, :registration_confirmation, %{})
  rescue
    error ->
      Logger.error(
        "registration_confirmation dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end
end
