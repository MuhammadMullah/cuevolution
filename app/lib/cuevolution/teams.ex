defmodule Cuevolution.Teams do
  @moduledoc """
  The Teams context: team registration and roster management (spec 005).
  """

  import Ecto.Query

  require Logger

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias Cuevolution.Teams.TeamInvitation
  alias Cuevolution.Teams.Workers.ExpireTeamInvitationWorker
  alias Ecto.Multi

  @invitation_validity_seconds 48 * 60 * 60

  @doc """
  Creates a team with `captain` as its Team Captain (spec 005 FR-001), and
  enrolls it into the Grassroots stage under the "team" category (spec 006
  default entry point) — atomically, so a team never exists without a
  Grassroots `StageParticipation`. The team's region is inherited from the
  captain, never user-supplied.

  Atomically claims the captain's roster slot (`players.team_id`) — if the
  captain is concurrently claimed by another `create_team/2` or
  `add_player_to_roster/2` call first, this one loses the race and the whole
  team creation rolls back (FR-007, DB-level, not just a changeset check).
  """
  def create_team(%Player{} = captain, attrs) do
    name = attrs["name"] || attrs[:name]

    changeset =
      Team.changeset(%Team{}, %{
        name: name,
        region_id: captain.region_id,
        captain_id: captain.id
      })

    Multi.new()
    |> Multi.insert(:team, changeset)
    |> Multi.insert(:stage_participation, fn %{team: team} ->
      Competitions.enroll_team_in_grassroots_changeset(team)
    end)
    |> Multi.update_all(
      :claim_captain,
      fn %{team: team} -> claim_query(captain.id, team.id) end,
      []
    )
    |> Multi.run(:verify_claim, fn _repo, %{claim_captain: {count, _}} ->
      if count == 1, do: {:ok, count}, else: {:error, :already_on_a_team}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{team: team}} -> {:ok, team}
      {:error, :team, changeset, _changes} -> {:error, changeset}
      {:error, :stage_participation, changeset, _changes} -> {:error, changeset}
      {:error, :verify_claim, :already_on_a_team, _changes} -> {:error, :already_on_a_team}
    end
  end

  @max_roster_size 8

  @doc """
  Adds `player` to `team`'s roster (spec 005 FR-002/FR-003/FR-004).

  The "same player claimed by two different teams" race is closed
  atomically at the DB level, same as `create_team/2`. The roster-size cap
  is a plain count-then-check — not fully race-proof against two *different*
  players being added to the *same* team in the same instant, but that's a
  far narrower window than the same-player race and isn't the scenario this
  task calls out as concurrency-critical.

  Once `team.roster_locked_at` is set (spec 005 FR-008 — the freeze applies
  once the team has been drawn into a group, per `Competitions.
  assign_to_group/2`'s `Teams.lock_roster/1` call; see that function's doc),
  this rejects with `{:error, :roster_frozen}` unless `opts[:override?]` is
  true (the admin-override path, `override_roster_change/3`).
  """
  def add_player_to_roster(%Team{} = team, %Player{} = player, opts \\ []) do
    Multi.new()
    |> Multi.run(:check_not_frozen, fn _repo, _changes -> check_not_frozen(team, opts) end)
    |> Multi.run(:check_capacity, fn repo, _changes ->
      count = repo.aggregate(from(p in Player, where: p.team_id == ^team.id), :count)
      if count < @max_roster_size, do: {:ok, count}, else: {:error, :roster_full}
    end)
    |> Multi.update_all(:claim_player, fn _changes -> claim_query(player.id, team.id) end, [])
    |> Multi.run(:verify_claim, fn _repo, %{claim_player: {count, _}} ->
      if count == 1, do: {:ok, count}, else: {:error, :already_on_a_team}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        updated_player = Repo.get!(Player, player.id)
        dispatch_team_assignment(updated_player, team)
        {:ok, updated_player}

      {:error, :check_not_frozen, :roster_frozen, _changes} ->
        {:error, :roster_frozen}

      {:error, :check_capacity, :roster_full, _changes} ->
        {:error, :roster_full}

      {:error, :verify_claim, :already_on_a_team, _changes} ->
        {:error, :already_on_a_team}
    end
  end

  defp check_not_frozen(team, opts) do
    if Keyword.get(opts, :override?, false) or is_nil(team.roster_locked_at) do
      {:ok, nil}
    else
      {:error, :roster_frozen}
    end
  end

  # A notification-dispatch failure is caught and logged — it never rolls
  # back the already-committed roster change, same policy as
  # `Accounts.register_player/1`'s registration-confirmation dispatch.
  defp dispatch_team_assignment(player, team) do
    team = Repo.preload(team, :captain)
    captain_name = "#{team.captain.first_name} #{team.captain.last_name}"

    Notifications.dispatch(player, :team_assignment, %{
      team_name: team.name,
      captain_name: captain_name
    })
  rescue
    error ->
      Logger.error(
        "team_assignment dispatch failed for player #{player.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end

  @min_roster_size 5

  @doc """
  Removes `player` from `team`'s roster (spec 005 FR-005). The roster is
  allowed to drop below the minimum — `eligible?/1` reflects that on its own
  next call rather than this function blocking the removal.

  Same freeze guard as `add_player_to_roster/3` (spec 005 FR-008 covers both
  add and remove, even though only the add-side has its own task number) —
  rejects with `{:error, :roster_frozen}` once `team.roster_locked_at` is
  set (from the team's first group draw onward, see `lock_roster/1`),
  unless `opts[:override?]` is true.

  ⚠️ Not specially guarded: removing the captain themselves. Spec 005 has no
  captain-succession/transfer mechanic (explicitly flagged as unresolved in
  its Edge Cases) — this function treats the captain like any roster member.
  """
  def remove_player_from_roster(%Team{} = team, %Player{} = player, opts \\ []) do
    with {:ok, nil} <- check_not_frozen(team, opts) do
      Player
      |> where(id: ^player.id, team_id: ^team.id)
      |> Repo.update_all(set: [team_id: nil])
      |> case do
        {1, _} -> {:ok, Repo.get!(Player, player.id)}
        {0, _} -> {:error, :not_on_this_team}
      end
    end
  end

  @doc """
  Deletes `team`, on behalf of `captain` — releases every roster member
  (including the captain) back to no-team status, in the same transaction
  as the delete. Any pending invitations for the team are cleaned up for
  free: `team_invitations.team_id` cascades `on_delete: :delete_all`, so
  they're removed along with the team rather than left dangling or flipped
  to "cancelled" first (there's no one left to show a "cancelled" status
  to once the team itself is gone).

  Only allowed before the team's roster freeze (`team.roster_locked_at`,
  see `lock_roster/1`) — the same gate `add_player_to_roster/3`/
  `remove_player_from_roster/3` use, which conveniently also guarantees no
  `Fixture`/`MatchResult` can exist yet to trip their `:restrict` foreign
  keys when `stage_participations` cascades from the team delete. No
  admin-override path: an already-drawn team must go through the admin
  roster-override flow instead of being deleted.

  Doesn't notify released teammates — matches `remove_player_from_roster/3`,
  which likewise only notifies on add, never on removal.
  """
  def delete_team(%Team{} = team, %Player{} = captain) do
    cond do
      team.captain_id != captain.id -> {:error, :not_captain}
      not is_nil(team.roster_locked_at) -> {:error, :roster_frozen}
      true -> do_delete_team(team)
    end
  end

  defp do_delete_team(team) do
    Multi.new()
    |> Multi.update_all(
      :release_roster,
      fn _changes ->
        from(p in Player, where: p.team_id == ^team.id, update: [set: [team_id: nil]])
      end,
      []
    )
    |> Multi.delete(:team, team)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, :team, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Admin override of the roster freeze (spec 005 FR-009, T061) — performs
  `action` (`:add` or `:remove`) bypassing only the `:check_not_frozen`
  guard (capacity/duplicate-membership/not-on-this-team checks stay
  active, since those are correctness invariants, not the freeze policy).
  Always logs via `Accounts.log_admin_action/4`, regardless of outcome.
  """
  def override_roster_change(action, %Team{} = team, %Player{} = player, %Admin{} = admin)
      when action in [:add, :remove] do
    result =
      case action do
        :add -> add_player_to_roster(team, player, override?: true)
        :remove -> remove_player_from_roster(team, player, override?: true)
      end

    log_override(action, team, player, admin, result)
    result
  end

  defp log_override(action, team, player, admin, result) do
    outcome =
      case result do
        {:ok, _player} -> "ok"
        {:error, reason} -> "error: #{inspect(reason)}"
      end

    Accounts.log_admin_action("override_roster_#{action}", admin, player,
      new_value: %{"team_id" => team.id, "outcome" => outcome}
    )
  end

  @doc """
  Invites `invitee` to join `team`'s roster — the captain-facing replacement
  for directly adding a player. Nothing here checks region/venue: teams are
  open to any registered, unattached player regardless of where they're
  based (no such restriction exists anywhere in this codebase, by design).

  Same guards as `add_player_to_roster/3` (frozen roster, capacity), plus
  rejecting a player already on a team outright rather than waiting for the
  eventual `accept_invitation/2` to discover it. The one-pending-per-team-
  player DB constraint is enforced via `unique_constraint/3` on the
  changeset, so a duplicate invite is a normal changeset error, not a raised
  `Ecto.ConstraintError`.

  On success, dispatches a `:team_invitation` notification (same
  rescue-and-log policy as `dispatch_team_assignment/2` — never rolls back
  an already-committed invitation) and schedules
  `ExpireTeamInvitationWorker` 48 hours out.
  """
  def invite_player(%Team{} = team, %Player{} = invitee) do
    Multi.new()
    |> Multi.run(:check_not_frozen, fn _repo, _changes -> check_not_frozen(team, []) end)
    |> Multi.run(:check_capacity, fn repo, _changes ->
      count = repo.aggregate(from(p in Player, where: p.team_id == ^team.id), :count)
      if count < @max_roster_size, do: {:ok, count}, else: {:error, :roster_full}
    end)
    |> Multi.run(:check_not_on_a_team, fn _repo, _changes ->
      if is_nil(invitee.team_id), do: {:ok, nil}, else: {:error, :already_on_a_team}
    end)
    |> Multi.insert(:invitation, fn _changes ->
      TeamInvitation.changeset(%TeamInvitation{}, %{
        team_id: team.id,
        player_id: invitee.id,
        invited_by_id: team.captain_id,
        status: "pending",
        expires_at: invitation_expiry()
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{invitation: invitation}} ->
        dispatch_team_invitation(invitee, team)
        schedule_invitation_expiry(invitation)
        {:ok, invitation}

      {:error, :check_not_frozen, :roster_frozen, _changes} ->
        {:error, :roster_frozen}

      {:error, :check_capacity, :roster_full, _changes} ->
        {:error, :roster_full}

      {:error, :check_not_on_a_team, :already_on_a_team, _changes} ->
        {:error, :already_on_a_team}

      {:error, :invitation, %Ecto.Changeset{} = changeset, _changes} ->
        if Keyword.has_key?(changeset.errors, :team_id) do
          {:error, :invitation_already_pending}
        else
          {:error, changeset}
        end
    end
  end

  defp invitation_expiry do
    DateTime.utc_now()
    |> DateTime.add(@invitation_validity_seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp schedule_invitation_expiry(invitation) do
    {:ok, _job} =
      %{"invitation_id" => invitation.id}
      |> ExpireTeamInvitationWorker.new(schedule_in: @invitation_validity_seconds)
      |> Oban.insert()

    :ok
  end

  defp dispatch_team_invitation(invitee, team) do
    team = Repo.preload(team, :captain)
    captain_name = "#{team.captain.first_name} #{team.captain.last_name}"

    Notifications.dispatch(invitee, :team_invitation, %{
      team_name: team.name,
      captain_name: captain_name
    })
  rescue
    error ->
      Logger.error(
        "team_invitation dispatch failed for player #{invitee.id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :ok
  end

  @doc """
  Accepts a pending `TeamInvitation` on `player`'s behalf. Re-checks
  `status`/`expires_at` against a fresh read (never trusts a struct the
  caller may have held onto), then reuses `add_player_to_roster/3` for the
  actual roster claim rather than duplicating its freeze/capacity/atomic-
  claim logic.

  On success, marks the invitation accepted and auto-cancels every other
  pending invitation `player` was holding (they're on a team now) — both via
  race-safe `status: "pending"`-scoped `update_all`s, so a concurrent
  expiry/decline/cancel never gets clobbered.
  """
  def accept_invitation(%TeamInvitation{} = invitation, %Player{} = player) do
    with {:ok, invitation} <- fetch_pending(invitation.id, player.id),
         team <- Repo.get!(Team, invitation.team_id),
         {:ok, updated_player} <- add_player_to_roster(team, player) do
      mark_responded(invitation, "accepted")
      cancel_other_pending_invitations(player.id, invitation.id)
      {:ok, updated_player}
    end
  end

  @doc """
  Declines a pending `TeamInvitation` on `player`'s behalf.
  """
  def decline_invitation(%TeamInvitation{} = invitation, %Player{} = player) do
    with {:ok, invitation} <- fetch_pending(invitation.id, player.id) do
      mark_responded(invitation, "declined")
      {:ok, invitation}
    end
  end

  @doc """
  Cancels a pending `TeamInvitation` on behalf of `captain` — verifies
  `captain` actually captains the invitation's team before touching it.
  """
  def cancel_invitation(%TeamInvitation{} = invitation, %Player{} = captain) do
    team = Repo.get!(Team, invitation.team_id)

    if team.captain_id == captain.id do
      case fetch_pending(invitation.id, invitation.player_id) do
        {:ok, invitation} ->
          mark_responded(invitation, "cancelled")
          {:ok, invitation}

        error ->
          error
      end
    else
      {:error, :not_captain}
    end
  end

  defp fetch_pending(invitation_id, player_id) do
    now = DateTime.utc_now()

    TeamInvitation
    |> where(
      [i],
      i.id == ^invitation_id and i.player_id == ^player_id and i.status == "pending"
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      %{expires_at: expires_at} = invitation -> check_not_expired(invitation, expires_at, now)
    end
  end

  defp check_not_expired(invitation, expires_at, now) do
    if DateTime.compare(expires_at, now) == :gt do
      {:ok, invitation}
    else
      {:error, :expired}
    end
  end

  defp mark_responded(invitation, status) do
    TeamInvitation
    |> where([i], i.id == ^invitation.id and i.status == "pending")
    |> Repo.update_all(
      set: [status: status, responded_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end

  defp cancel_other_pending_invitations(player_id, except_invitation_id) do
    TeamInvitation
    |> where(
      [i],
      i.player_id == ^player_id and i.status == "pending" and i.id != ^except_invitation_id
    )
    |> Repo.update_all(
      set: [status: "cancelled", responded_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end

  @doc """
  Pending, unexpired invitations for `player_id` — the banner's data source
  (`CuevolutionWeb.PlayerAuth.on_mount/4`). Preloads `team: :captain` since
  the banner shows both the team name and who sent the invite.
  """
  def list_pending_invitations_for_player(player_id) do
    now = DateTime.utc_now()

    TeamInvitation
    |> where([i], i.player_id == ^player_id and i.status == "pending" and i.expires_at > ^now)
    |> order_by(asc: :inserted_at)
    |> preload(team: :captain)
    |> Repo.all()
  end

  @doc """
  Pending, unexpired invitations `team_id` has sent — the captain
  dashboard's "invitations sent" list (with a cancel action).
  """
  def list_pending_invitations_for_team(team_id) do
    now = DateTime.utc_now()

    TeamInvitation
    |> where([i], i.team_id == ^team_id and i.status == "pending" and i.expires_at > ^now)
    |> order_by(asc: :inserted_at)
    |> preload(:player)
    |> Repo.all()
  end

  @doc """
  Looks up a pending invitation for `player_id` by id, scoped so a player
  can only ever act on their own invitations — used by the accept/decline
  event hook before calling `accept_invitation/2`/`decline_invitation/2`.
  Returns `nil` (not an error tuple) so callers can pattern-match a missing
  invitation the same way as any other "not found" lookup.
  """
  def get_pending_invitation_for_player(invitation_id, player_id) do
    TeamInvitation
    |> where([i], i.id == ^invitation_id and i.player_id == ^player_id and i.status == "pending")
    |> Repo.one()
  end

  @doc """
  Looks up a pending invitation by id, scoped to `team_id` — the captain
  dashboard's counterpart to `get_pending_invitation_for_player/2`, used
  before `cancel_invitation/2` so a captain can only cancel their own
  team's invitations.
  """
  def get_pending_invitation_for_team_and_id(team_id, invitation_id) do
    TeamInvitation
    |> where([i], i.id == ^invitation_id and i.team_id == ^team_id and i.status == "pending")
    |> Repo.one()
  end

  @doc """
  Locks `team_id`'s roster — called from two places, both idempotent no-ops
  once already locked: `Competitions.assign_to_group/2` (the moment a team
  is first drawn into a group, ahead of any `Fixture` existing for it — this
  is the primary trigger, superseding spec 005's original "first recorded
  Match Result" assumption so a captain can no longer add/remove players
  once the team's been drawn) and `Competitions.record_result/3` (kept as a
  harmless safety net for any path that somehow reaches a result without a
  prior group assignment). Plain conditional `update_all`, no `Multi`
  needed here — the `is_nil` guard alone makes it naturally idempotent.
  """
  def lock_roster(team_id) do
    Team
    |> where([t], t.id == ^team_id and is_nil(t.roster_locked_at))
    |> Repo.update_all(set: [roster_locked_at: DateTime.utc_now() |> DateTime.truncate(:second)])
  end

  @doc """
  Whether `team`'s roster is within the required 5-8 range (spec 005 FR-005)
  — always derived live from `players.team_id`, never a cached column.
  """
  def eligible?(%Team{} = team) do
    count = Repo.aggregate(from(p in Player, where: p.team_id == ^team.id), :count)
    count >= @min_roster_size and count <= @max_roster_size
  end

  defp claim_query(player_id, team_id) do
    from(p in Player,
      where: p.id == ^player_id and is_nil(p.team_id),
      update: [set: [team_id: ^team_id]]
    )
  end

  @doc """
  Filterable team directory query — the Teams-context counterpart of
  `Accounts.list_players_filtered/1`, backing the admin Directory's "Teams"
  kind. Supported filters: `:region_id`, `:name` (case-insensitive
  substring search), `:stage_id` (via an indexed `EXISTS` subquery, same
  approach as `Accounts.list_players_filtered/1`). Preloads `:roster` only
  (no caller needs `:captain` — dropped to save a query) since callers use
  it just for `length/1`, not the roster's contents.
  """
  def list_teams_filtered(filters \\ %{}) do
    Team
    |> filter_by_region(filters[:region_id])
    |> filter_by_name(filters[:name])
    |> filter_by_stage(filters[:stage_id])
    |> order_by(asc: :name)
    |> preload([:region, :roster])
    |> Repo.all()
  end

  defp filter_by_region(query, nil), do: query
  defp filter_by_region(query, region_id), do: where(query, region_id: ^region_id)

  defp filter_by_name(query, nil), do: query

  defp filter_by_name(query, name) do
    pattern = "%" <> String.replace(name, ~w(% _), fn c -> "\\" <> c end) <> "%"
    where(query, [t], ilike(t.name, ^pattern))
  end

  defp filter_by_stage(query, nil), do: query

  defp filter_by_stage(query, stage_id) do
    participant_ids =
      from(sp in StageParticipation, where: sp.stage_id == ^stage_id, select: sp.team_id)

    where(query, [t], t.id in subquery(participant_ids))
  end
end
