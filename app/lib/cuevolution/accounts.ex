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
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Competitions
  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias Ecto.Multi

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
  Registers a player (spec 003 US1), enrolls them into the Grassroots stage
  under their gender category (spec 006 default entry point), and dispatches
  a registration-confirmation notification. The stage enrollment is created
  atomically with the account — a player never exists without a Grassroots
  `StageParticipation`. The notification dispatch, by contrast, runs after
  commit and its failure is caught and logged rather than rolling back the
  already-committed account (spec 002).
  """
  def register_player(attrs) do
    Multi.new()
    |> Multi.insert(:player, Player.registration_changeset(%Player{}, attrs))
    |> Multi.insert(:stage_participation, fn %{player: player} ->
      Competitions.enroll_player_in_grassroots_changeset(player)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} ->
        dispatch_registration_confirmation(player)
        {:ok, player}

      {:error, :player, changeset, _changes} ->
        {:error, changeset}

      {:error, :stage_participation, changeset, _changes} ->
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

  @doc """
  Looks up a player by email or username (case-insensitive), or `nil` if no
  match — used by the password-reset request flow (spec 011), which must
  not otherwise reveal whether a given login is registered.
  """
  def get_player_by_login(login) when is_binary(login) do
    Repo.one(player_by_login_query(login))
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

  @doc """
  Issues a fresh password-reset token for `player` and enqueues the reset
  email (spec 011). Any previously issued, unused reset token for this
  player is invalidated first — only the most recently requested link is
  ever valid (spec.md FR-005).

  `reset_password_url_fun` receives the URL-safe encoded token and must
  return the full reset URL — callers build this with their own route
  helper (e.g. `&url(~p"/reset-password/\#{&1}")`) rather than this context
  hardcoding a path.
  """
  def deliver_player_reset_password_instructions(%Player{} = player, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    Repo.delete_all(PlayerToken.by_player_and_contexts_query(player, ["reset_password"]))

    {encoded_token, token_struct} = PlayerToken.build_reset_password_token(player)
    Repo.insert!(token_struct)

    %{"player_id" => player.id, "reset_url" => reset_password_url_fun.(encoded_token)}
    |> SendPasswordResetEmailWorker.new()
    |> Oban.insert()
  end

  @doc """
  Looks up the player a password-reset token belongs to — `nil` if the
  token is malformed, unknown, expired, or already consumed (spec 011
  FR-006 deliberately doesn't distinguish these cases to the caller).
  """
  def get_player_by_reset_password_token(token) do
    case PlayerToken.verify_reset_password_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Sets a player's new password and invalidates every one of their tokens —
  including the reset token just used and any other active sessions (spec
  011 FR-008) — in a single transaction.
  """
  def reset_player_password(%Player{} = player, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:player, Player.reset_password_changeset(player, attrs))
    |> Ecto.Multi.delete_all(:tokens, PlayerToken.by_player_and_contexts_query(player, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, :player, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc "Updates a player's notification preference (spec 003 US2)."
  def update_notification_preference(%Player{} = player, preference) do
    player
    |> Player.notification_preference_changeset(%{notification_preference: preference})
    |> Repo.update()
  end

  @doc "Whether `player` is locked out of changing their region (spec 003 US3/FR-008) — locked once they have a recorded match result, not merely a scheduled fixture."
  def region_locked?(%Player{} = player) do
    Competitions.player_has_match_result?(player.id)
  end

  @doc "Updates a player's editable personal details: username, date of birth, town."
  def update_personal_details(%Player{} = player, attrs) do
    player
    |> Player.personal_details_changeset(attrs)
    |> Repo.update()
  end

  @doc "Updates `player`'s region, rejecting the change once `region_locked?/1` is true (spec 003 US3)."
  def change_region(%Player{} = player, region_id) do
    if region_locked?(player) do
      {:error, :region_locked}
    else
      player
      |> Player.region_changeset(%{region_id: region_id})
      |> Repo.update()
    end
  end

  @doc """
  Updates `player`'s preferred venue only, keeping their region unchanged —
  always allowed, even once `region_locked?/1` is true.
  """
  def change_venue(%Player{} = player, venue_id) do
    player
    |> Player.venue_changeset(%{preferred_venue_id: venue_id})
    |> Repo.update()
  end

  @doc """
  Updates `player`'s region and preferred venue together, rejecting the
  change once `region_locked?/1` is true — a venue only makes sense within
  the region it belongs to, so changing region always requires picking a
  venue from the new one in the same update.
  """
  def change_region_and_venue(%Player{} = player, region_id, venue_id) do
    if region_locked?(player) do
      {:error, :region_locked}
    else
      player
      |> Player.region_and_venue_changeset(%{region_id: region_id, preferred_venue_id: venue_id})
      |> Repo.update()
    end
  end

  @doc "Sets a new password for a signed-in player after confirming their current one."
  def update_player_password(%Player{} = player, attrs) do
    player
    |> Player.update_password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Warnings that must be shown and explicitly confirmed before anonymizing
  `player` (spec 010 FR-007) — `[:captain]` if they captain a team,
  `[:pending_fixtures]` if they have a fixture with no result yet, both,
  or `[]`. Never blocks — the caller (`PlayerDetailLive` for an admin,
  `ProfileSettingsLive` for a player deactivating their own account) decides
  whether to proceed after showing these.
  """
  def anonymize_warnings(%Player{} = player) do
    []
    |> add_warning_if(:captain, Repo.get_by(Team, captain_id: player.id) != nil)
    |> add_warning_if(:pending_fixtures, Competitions.player_has_pending_fixtures?(player.id))
  end

  defp add_warning_if(warnings, warning, true), do: [warning | warnings]
  defp add_warning_if(warnings, _warning, false), do: warnings

  @doc """
  Anonymizes `player` (spec 010 FR-004/FR-007) — clears PII, sets
  `anonymized_at`, and logs the action. Historical `match_results`/
  `cuevo_points_entries` are untouched (they reference the `StageParticipation`,
  not the `Player`, directly). Login is naturally rejected afterward since
  the anonymized email/username no longer match what the player would enter.
  """
  def anonymize_player(%Player{} = player, %Admin{} = admin) do
    Multi.new()
    |> Multi.update(:player, Player.anonymize_changeset(player))
    |> Multi.run(:log, fn _repo, %{player: updated} ->
      log_admin_action("anonymize_player", admin, updated)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, :player, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Self-service account deactivation: a player anonymizing their own account
  (same effect as `anonymize_player/2`, minus the admin audit log entry,
  since no admin is involved) and invalidating every one of their session
  tokens in the same transaction, so the deactivation immediately signs
  them out everywhere.
  """
  def deactivate_player(%Player{} = player) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:player, Player.anonymize_changeset(player))
    |> Ecto.Multi.delete_all(:tokens, PlayerToken.by_player_and_contexts_query(player, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, :player, changeset, _changes} -> {:error, changeset}
    end
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
    pattern = "%" <> escape_like_pattern(username) <> "%"
    where(query, [p], ilike(p.username, ^pattern))
  end

  @doc """
  Name/username typeahead search for the admin Draws page's participant
  picker (individual categories only — Teams go through
  `Teams.list_teams_filtered/1`). Matches full name or username,
  case-insensitive substring, excludes anonymized players. Capped to a
  handful of results since it backs a live-search dropdown, not a listing.
  """
  def search_players(category, query) when category in ["male", "female"] do
    pattern = "%" <> escape_like_pattern(query) <> "%"

    Player
    |> where([p], p.gender == ^category and is_nil(p.anonymized_at))
    |> where(
      [p],
      ilike(fragment("? || ' ' || ?", p.first_name, p.last_name), ^pattern) or
        ilike(p.username, ^pattern)
    )
    |> order_by(asc: :first_name, asc: :last_name)
    |> limit(6)
    |> Repo.all()
  end

  defp escape_like_pattern(value), do: String.replace(value, ~w(% _), fn c -> "\\" <> c end)

  @doc """
  All regions in seed order (`priv/repo/seeds/regions_seeds.exs`), which is
  the fixed display order used throughout the admin console — regions have
  no explicit ordinal column, so `inserted_at` (set once at seed time and
  never touched again) is what preserves it.
  """
  def list_regions do
    Repo.all(from r in Region, order_by: r.inserted_at)
  end

  @doc """
  Players in `region_id` who registered with a free-text "Other" venue
  instead of picking one off the preloaded list (spec 004) — the admin
  Venues page surfaces these so an admin can add popular ones to the real
  list.
  """
  def list_custom_venue_submissions(region_id) do
    Player
    |> where([p], p.region_id == ^region_id)
    |> where([p], not is_nil(p.other_venue_name) and p.other_venue_name != "")
    |> order_by(asc: :other_venue_name)
    |> Repo.all()
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
