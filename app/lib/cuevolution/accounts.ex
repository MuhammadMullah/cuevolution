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
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Notifications
  alias Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker
  alias Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue
  alias Ecto.Multi

  # Registration remains open after this point, but those accounts belong to
  # the next tournament season. Stored timestamps are UTC-naive in this app;
  # midnight on 21 September 2026 EAT is 21:00 UTC on 20 September.
  @tournament_registration_cutoff ~N[2026-09-20 21:00:00]

  @doc "Returns the cutoff timestamp for eligibility in the current tournament season."
  def tournament_registration_cutoff, do: @tournament_registration_cutoff

  @doc """
  Whether a player registered before the current tournament season cutoff,
  or was individually granted `:tournament_eligibility_override` afterward.
  """
  def tournament_eligible?(%Player{tournament_eligibility_override: true}), do: true

  def tournament_eligible?(%Player{inserted_at: inserted_at}) do
    NaiveDateTime.compare(inserted_at, @tournament_registration_cutoff) == :lt
  end

  @doc """
  Grants `:tournament_eligibility_override` to every player who registered
  in `[from, to)` (UTC-naive, matching `inserted_at`) — the tournament
  committee's one-off decision to admit specific late registrants into this
  season without moving `tournament_registration_cutoff/0` itself, which
  stays in force for anyone registering late from here on. Idempotent
  (skips players who already have the override) and logs each grant as a
  system `AdminActionLog` entry. Returns the granted players' usernames.
  """
  def grant_tournament_eligibility_override(%NaiveDateTime{} = from, %NaiveDateTime{} = to) do
    Repo.transaction(fn ->
      Player
      |> where([p], p.inserted_at >= ^from and p.inserted_at < ^to)
      |> where([p], p.tournament_eligibility_override == false)
      |> Repo.all()
      |> Enum.map(fn player ->
        {:ok, updated} =
          player
          |> Ecto.Changeset.change(tournament_eligibility_override: true)
          |> Repo.update()

        log_system_action("grant_tournament_eligibility_override", updated,
          prior_value: %{"tournament_eligibility_override" => false},
          new_value: %{"tournament_eligibility_override" => true}
        )

        updated.username
      end)
    end)
  end

  @doc """
  Authenticates an admin by email and password.

  Always runs a bcrypt comparison (against a dummy hash when the email
  doesn't match anyone, or matches an admin who hasn't completed account
  setup yet and so has no `hashed_password`) so none of those failure modes
  can be told apart by response time.
  """
  def authenticate_admin(email, password) when is_binary(email) and is_binary(password) do
    case Repo.get_by(Admin, email: email) do
      %Admin{hashed_password: hashed} = admin
      when is_binary(hashed) and admin.suspended_at == nil and admin.removed_at == nil ->
        if Bcrypt.verify_pass(password, hashed) do
          {:ok, admin}
        else
          {:error, :invalid_credentials}
        end

      _ ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc "Lists all active and suspended admins for the admin-management page, most recently invited first."
  def list_admins do
    Repo.all(from a in Admin, where: is_nil(a.removed_at), order_by: [desc: a.inserted_at])
  end

  @doc """
  Invites a new admin: creates a pending record (email + role, no password
  yet), logs the action against `inviter` (spec 001 FR-005 audit trail), and
  enqueues the account-setup email. `setup_url_fun` receives the URL-safe
  encoded token and must return the full setup URL — callers build this
  with their own route helper rather than this context hardcoding a path.
  """
  def invite_admin(%Admin{} = inviter, attrs, setup_url_fun) when is_function(setup_url_fun, 1) do
    if Admin.can?(inviter, :manage_admins) do
      do_invite_admin(inviter, attrs, setup_url_fun)
    else
      {:error, :unauthorized}
    end
  end

  defp do_invite_admin(%Admin{} = inviter, attrs, setup_url_fun) do
    Multi.new()
    |> Multi.insert(:admin, Admin.invite_changeset(%Admin{}, attrs))
    |> Multi.run(:token, fn repo, %{admin: admin} ->
      {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)
      repo.insert(token_struct)
      {:ok, encoded_token}
    end)
    |> Multi.run(:log, fn _repo, %{admin: admin} ->
      log_admin_action("invite_admin", inviter, admin, new_value: %{"role" => admin.role})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: admin, token: encoded_token}} ->
        %{"admin_id" => admin.id, "setup_url" => setup_url_fun.(encoded_token)}
        |> SendAdminInvitationEmailWorker.new()
        |> Oban.insert()

        {:ok, admin}

      {:error, :admin, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_admin_role(%Admin{} = actor, %Admin{} = target, role)
      when is_binary(role) do
    if Admin.can?(actor, :manage_admins) and Admin.manageable_by?(actor, target) and
         role in (Admin.invitable_roles() ++ ["super_admin"]) and
         (actor.role == "super_admin" or role != "super_admin") do
      target
      |> Ecto.Changeset.change(role: role)
      |> Repo.update()
      |> log_admin_change(actor, target, "update_admin_role", role)
    else
      {:error, :unauthorized}
    end
  end

  def suspend_admin(%Admin{} = actor, %Admin{} = target) do
    if Admin.can?(actor, :manage_admins) and Admin.manageable_by?(actor, target) and
         actor.id != target.id do
      target
      |> Ecto.Changeset.change(suspended_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def reinstate_admin(%Admin{} = actor, %Admin{} = target) do
    if Admin.can?(actor, :manage_admins) and Admin.manageable_by?(actor, target) do
      target |> Ecto.Changeset.change(suspended_at: nil) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def remove_admin(%Admin{} = actor, %Admin{} = target) do
    if Admin.can?(actor, :manage_admins) and Admin.manageable_by?(actor, target) and
         actor.id != target.id do
      target
      |> Ecto.Changeset.change(removed_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  defp log_admin_change({:ok, _updated} = result, actor, target, action, role) do
    _ =
      log_admin_action(action, actor, target,
        prior_value: %{"role" => target.role},
        new_value: %{"role" => role}
      )

    result
  end

  defp log_admin_change(error, _actor, _target, _action, _role), do: error

  @doc """
  Looks up the admin a setup token belongs to — `nil` if the token is
  malformed, unknown, expired, or already consumed.
  """
  def get_admin_by_setup_token(token) do
    case AdminToken.verify_admin_setup_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Completes an invited admin's account setup — sets their password and
  mobile number and invalidates every one of their tokens, including the
  setup token just used.
  """
  def complete_admin_setup(%Admin{} = admin, attrs) do
    Multi.new()
    |> Multi.update(:admin, Admin.setup_changeset(admin, attrs))
    |> Multi.delete_all(:tokens, AdminToken.by_admin_and_contexts_query(admin, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: admin}} -> {:ok, admin}
      {:error, :admin, changeset, _changes} -> {:error, changeset}
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

  @doc "Records an audit action performed by the system without an admin actor."
  def log_system_action(action_type, entity, opts) do
    %AdminActionLog{}
    |> AdminActionLog.changeset(%{
      actor_type: "system",
      action_type: action_type,
      entity_type: entity.__struct__ |> to_string() |> String.trim_leading("Elixir."),
      entity_id: entity.id,
      prior_value: Keyword.get(opts, :prior_value),
      new_value: Keyword.get(opts, :new_value)
    })
    |> Repo.insert()
  end

  @doc "Lists recent audit entries, optionally filtered by action type."
  def list_admin_action_logs(action_type \\ nil) do
    AdminActionLog
    |> maybe_filter_action_type(action_type)
    |> order_by(desc: :inserted_at)
    |> limit(300)
    |> preload(:admin)
    |> Repo.all()
  end

  defp maybe_filter_action_type(query, nil), do: query
  defp maybe_filter_action_type(query, ""), do: query
  defp maybe_filter_action_type(query, action_type), do: where(query, action_type: ^action_type)

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

  @doc "Whether an identification number is already registered."
  def identification_number_taken?(""), do: false

  def identification_number_taken?(identification_number) when is_binary(identification_number) do
    identification_number = identification_number |> String.trim() |> String.downcase()

    Repo.exists?(
      from p in Player,
        where: fragment("lower(trim(?))", p.identification_number) == ^identification_number
    )
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
    |> Multi.run(:stage_participation, fn repo, %{player: player} ->
      if tournament_eligible?(player) do
        repo.insert(Competitions.enroll_player_in_grassroots_changeset(player))
      else
        {:ok, nil}
      end
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

  @doc "Saves a player's identification details required for match verification."
  def update_player_identification(%Player{} = player, attrs) do
    player
    |> Player.identification_changeset(attrs)
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
  Updates `player`'s preferred venue on their behalf, requiring
  `:manage_players` and logging the change via `log_admin_action/4` — the
  admin-initiated counterpart to `change_venue/2`. Like `change_venue/2`,
  never checks `region_locked?/1`: this only ever changes venue within the
  player's existing region.
  """
  def admin_change_venue(%Player{} = player, venue_id, %Admin{} = admin) do
    do_admin_change_location(
      player,
      player.region_id,
      venue_id,
      admin,
      "change_player_venue",
      fn ->
        changeset =
          player
          |> Player.venue_changeset(%{preferred_venue_id: venue_id})
          |> Ecto.Changeset.add_error(
            :preferred_venue_id,
            "is not an active venue in this region"
          )

        {:error, changeset}
      end
    )
  end

  @doc "Updates a player's region and preferred venue on behalf of an authorized admin."
  def admin_change_location(%Player{} = player, region_id, venue_id, %Admin{} = admin) do
    do_admin_change_location(player, region_id, venue_id, admin, "change_player_location", fn ->
      {:error, :invalid_location}
    end)
  end

  defp do_admin_change_location(
         %Player{} = player,
         region_id,
         venue_id,
         %Admin{} = admin,
         action_type,
         invalid_location
       ) do
    with true <- Admin.can?(admin, :manage_players),
         %Venue{} = venue <- Venues.get_active_in_region(venue_id, region_id) do
      persist_location_change(
        player,
        venue,
        region_id,
        admin,
        action_type,
        player.region_id,
        player.preferred_venue_id
      )
    else
      false -> {:error, :unauthorized}
      nil -> invalid_location.()
    end
  end

  defp persist_location_change(
         player,
         venue,
         region_id,
         admin,
         action_type,
         prior_region_id,
         prior_venue_id
       ) do
    Multi.new()
    |> Multi.update(
      :player,
      Player.region_and_venue_changeset(player, %{
        region_id: region_id,
        preferred_venue_id: venue.id
      })
    )
    |> Multi.run(:log, fn _repo, %{player: updated} ->
      log_location_change(
        action_type,
        admin,
        updated,
        prior_region_id,
        prior_venue_id,
        region_id,
        venue.id
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player: updated}} ->
        updated = Repo.preload(updated, [:region, :preferred_venue], force: true)

        maybe_dispatch_location_update(
          updated,
          prior_region_id,
          prior_venue_id,
          region_id,
          venue.id
        )

        {:ok, updated}

      {:error, :player, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp maybe_dispatch_location_update(
         updated,
         prior_region_id,
         prior_venue_id,
         region_id,
         venue_id
       ) do
    if prior_region_id != region_id or prior_venue_id != venue_id do
      dispatch_location_update(updated)
    end
  end

  defp log_location_change(
         "change_player_venue",
         admin,
         player,
         _prior_region_id,
         prior_venue_id,
         _region_id,
         venue_id
       ) do
    log_admin_action("change_player_venue", admin, player,
      prior_value: %{"preferred_venue_id" => prior_venue_id},
      new_value: %{"preferred_venue_id" => venue_id}
    )
  end

  defp log_location_change(
         action_type,
         admin,
         player,
         prior_region_id,
         prior_venue_id,
         region_id,
         venue_id
       ) do
    log_admin_action(action_type, admin, player,
      prior_value: %{"region_id" => prior_region_id, "preferred_venue_id" => prior_venue_id},
      new_value: %{"region_id" => region_id, "preferred_venue_id" => venue_id}
    )
  end

  defp dispatch_location_update(player) do
    Notifications.dispatch(player, :player_location_updated, %{
      region_name: player.region.name,
      venue_name: player.preferred_venue.name
    })
  rescue
    error ->
      Logger.error(
        "player_location_updated dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end

  @doc """
  Assigns selected custom-venue submissions to one active canonical venue.

  The operation is region-scoped, only accepts players who still have a
  custom venue value, clears that value after assignment, and writes one
  audit entry per player.
  """
  def admin_assign_custom_venues(player_ids, venue_id, %Admin{} = admin) do
    cond do
      not Admin.can?(admin, :manage_players) ->
        {:error, :unauthorized}

      not is_binary(venue_id) ->
        {:error, :invalid_venue}

      true ->
        player_ids = if is_list(player_ids), do: Enum.uniq(player_ids), else: []
        venue = Repo.get_by(Venue, id: venue_id, active: true)

        cond do
          player_ids == [] -> {:error, :invalid_selection}
          Enum.any?(player_ids, &(not valid_uuid?(&1))) -> {:error, :invalid_selection}
          is_nil(venue) -> {:error, :invalid_venue}
          true -> assign_custom_venues(player_ids, venue, admin)
        end
    end
  end

  defp assign_custom_venues(player_ids, venue, admin) do
    players =
      Player
      |> where(
        [p],
        p.id in ^player_ids and p.region_id == ^venue.region_id and
          not is_nil(p.other_venue_name) and p.other_venue_name != ""
      )
      |> Repo.all()

    if length(players) != length(player_ids) do
      {:error, :stale_selection}
    else
      persist_custom_venue_assignments(players, player_ids, venue, admin)
    end
  end

  defp persist_custom_venue_assignments(players, player_ids, venue, admin) do
    Multi.new()
    |> Multi.update_all(
      :players,
      from(p in Player, where: p.id in ^player_ids),
      set: [preferred_venue_id: venue.id, other_venue_name: nil]
    )
    |> Multi.run(:logs, fn repo, _changes ->
      insert_custom_venue_logs(repo, players, venue, admin)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{players: {count, _}}} -> {:ok, count}
      {:error, :players, reason, _changes} -> {:error, reason}
      {:error, :logs, reason, _changes} -> {:error, reason}
    end
  end

  defp insert_custom_venue_logs(repo, players, venue, admin) do
    Enum.reduce_while(players, {:ok, 0}, fn player, {:ok, count} ->
      player
      |> custom_venue_log_changeset(venue, admin)
      |> repo.insert()
      |> accumulate_custom_venue_log(count)
    end)
  end

  defp custom_venue_log_changeset(player, venue, admin) do
    AdminActionLog.changeset(%AdminActionLog{}, %{
      admin_id: admin.id,
      action_type: "consolidate_custom_venue",
      entity_type: "Cuevolution.Accounts.Player",
      entity_id: player.id,
      prior_value: %{
        "preferred_venue_id" => player.preferred_venue_id,
        "other_venue_name" => player.other_venue_name
      },
      new_value: %{
        "preferred_venue_id" => venue.id,
        "other_venue_name" => nil
      }
    })
  end

  defp accumulate_custom_venue_log({:ok, _log}, count), do: {:cont, {:ok, count + 1}}
  defp accumulate_custom_venue_log({:error, changeset}, _count), do: {:halt, {:error, changeset}}

  defp valid_uuid?(id) do
    is_binary(id) and match?({:ok, _}, Ecto.UUID.cast(id))
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
    if Admin.can?(admin, :anonymize_users) do
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
    else
      {:error, :unauthorized}
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

  Supported filters: `:region_id`, `:venue_id` (`preferred_venue_id`),
  `:category` (gender), `:username` (case-insensitive substring search),
  `:stage_id` (current `Competitions.StageParticipation`, via an indexed
  `EXISTS` subquery rather than loading every participation into memory —
  see the admin Directory, which used to do exactly that).
  """
  def list_players_filtered(filters) do
    Player
    |> filter_by_region(filters[:region_id])
    |> filter_by_venue(filters[:venue_id])
    |> filter_by_category(filters[:category])
    |> filter_by_username(filters[:username])
    |> filter_by_stage(filters[:stage_id])
    |> order_by(asc: :username)
    |> preload(:region)
    |> maybe_limit(filters[:limit])
    |> maybe_offset(filters[:offset])
    |> Repo.all()
  end

  def count_players_filtered(filters) do
    Player
    |> filter_by_region(filters[:region_id])
    |> filter_by_venue(filters[:venue_id])
    |> filter_by_category(filters[:category])
    |> filter_by_username(filters[:username])
    |> filter_by_stage(filters[:stage_id])
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, value), do: limit(query, ^value)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, value), do: offset(query, ^value)

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  defp filter_by_venue(query, nil), do: query
  defp filter_by_venue(query, venue_id), do: where(query, preferred_venue_id: ^venue_id)

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, category), do: where(query, gender: ^category)

  defp filter_by_username(query, nil), do: query

  defp filter_by_username(query, username) do
    pattern = "%" <> escape_like_pattern(username) <> "%"
    where(query, [p], ilike(p.username, ^pattern))
  end

  defp filter_by_stage(query, nil), do: query

  defp filter_by_stage(query, stage_id) do
    participant_ids =
      from(sp in StageParticipation, where: sp.stage_id == ^stage_id, select: sp.player_id)

    where(query, [p], p.id in subquery(participant_ids))
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

  @doc "Returns active players matching a team invitation query by name or username."
  def search_players_for_team_invite(query) when is_binary(query) do
    query = String.trim(query)

    if String.length(query) < 2 do
      []
    else
      pattern = "%" <> escape_like_pattern(query) <> "%"

      Player
      |> where([p], is_nil(p.anonymized_at))
      |> where(
        [p],
        ilike(p.username, ^pattern) or
          ilike(p.first_name, ^pattern) or
          ilike(p.last_name, ^pattern) or
          ilike(fragment("? || ' ' || ?", p.first_name, p.last_name), ^pattern)
      )
      |> order_by(asc: :first_name, asc: :last_name)
      |> limit(6)
      |> Repo.all()
    end
  end

  @doc "Returns canonical and previously submitted venue names for player typeahead suggestions."
  def search_venue_options(region_id, query) when is_binary(region_id) and is_binary(query) do
    query = String.trim(query)

    if String.length(query) < 2 do
      []
    else
      do_search_venue_options(region_id, query)
    end
  end

  defp do_search_venue_options(region_id, query) do
    pattern = "%" <> escape_like_pattern(query) <> "%"

    official_names =
      Venue
      |> where([v], v.region_id == ^region_id and v.active and ilike(v.name, ^pattern))
      |> order_by(asc: :name)
      |> limit(6)
      |> select([v], %{id: v.id, name: v.name, kind: "venue"})
      |> Repo.all()

    custom_names =
      Player
      |> where(
        [p],
        p.region_id == ^region_id and not is_nil(p.other_venue_name) and
          p.other_venue_name != "" and ilike(p.other_venue_name, ^pattern)
      )
      |> order_by(asc: :other_venue_name)
      |> limit(12)
      |> select([p], %{id: nil, name: p.other_venue_name, kind: "custom"})
      |> Repo.all()

    merge_venue_suggestions(official_names, custom_names)
  end

  defp merge_venue_suggestions(official_names, custom_names) do
    custom_names
    |> Enum.reduce(official_names, fn suggestion, acc ->
      normalized = String.downcase(String.trim(suggestion.name))

      if Enum.any?(acc, &(String.downcase(String.trim(&1.name)) == normalized)) do
        acc
      else
        acc ++ [suggestion]
      end
    end)
    |> Enum.take(8)
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
    |> select([p], %{id: p.id, username: p.username, other_venue_name: p.other_venue_name})
    |> Repo.all()
  end

  @doc """
  Returns the base query for players whose `preferred_venue_id` matches the given venue.
  Anonymized players are excluded. Callers can add their own filters, ordering,
  or preloads before running the query.
  """
  def list_players_by_preferred_venue(venue_id) do
    from p in Player, where: p.preferred_venue_id == ^venue_id and is_nil(p.anonymized_at)
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
