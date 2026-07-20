# Competitions-context integration points: Accounts.region_locked?/1, Accounts.anonymize_player/2, Teams.add_player_to_roster/2 freeze clause

Researched 2026-07-13 against branch `admin-app-design-improvement`. Sources: `project-scope/tasks.md` (T027/T028/T032/T058/T061), `project-scope/specs/003-player-registration/spec.md` (US3, FR-008), `project-scope/specs/005-team-management/spec.md` (FR-008/FR-009), `project-scope/specs/010-admin-directory-data-privacy/spec.md` (US2, FR-004..FR-008), and full reads of `lib/cuevolution/accounts.ex`, `lib/cuevolution/accounts/player.ex`, `lib/cuevolution/teams.ex`, `lib/cuevolution/teams/team.ex`, `lib/cuevolution_web/live/player/profile_settings_live.ex(.heex)`, `lib/cuevolution_web/live/admin/player_detail_live.ex(.heex)`.

---

## 1. `Cuevolution.Accounts.region_locked?/1` (T027) + `Accounts.change_region/2` (T028)

### Current state
Neither function exists in `lib/cuevolution/accounts.ex` (398 lines total; grepped for `region_locked`, `change_region` — zero hits in `lib/` or `test/`). `Cuevolution.Accounts.Player` (`lib/cuevolution/accounts/player.ex`) has no region-update changeset — only `registration_changeset/2` (casts `:region_id` at creation, line 58) and `notification_preference_changeset/2` (lines 98-104, the template T028 should mirror). No migration/schema work needed for the lock itself — the lock is *derived*, per spec 003 Key Entities: "region-locked flag (derived from existence of a `Match Result`, spec 008 — not from fixture/draw existence)". `Player` gets no new persisted column.

### Insertion point
Add both functions to `lib/cuevolution/accounts.ex`, near `update_notification_preference/2` (whichever line it lands at post `T026`; as of this read the last defined public function is `list_regions/0` around line 255, and `username_taken?/1`/`email_taken?/1` establish the file's `?`-predicate convention at lines 88-100). Suggested shape:

```elixir
@doc "Whether region_id changes are locked for `player` (spec 003 FR-008) — locked once Competitions.MatchResult exists for them."
def region_locked?(%Player{} = player) do
  Competitions.player_has_match_result?(player.id)
end

@doc "Changes player.region_id, enforced by region_locked?/1 (spec 003 FR-008)."
def change_region(%Player{} = player, region_id) do
  if region_locked?(player) do
    {:error, :region_locked}
  else
    player
    |> Player.region_changeset(%{region_id: region_id})
    |> Repo.update()
  end
end
```
This requires adding `Player.region_changeset/2` to `lib/cuevolution/accounts/player.ex` (cast `[:region_id]`, `validate_required([:region_id])`, `foreign_key_constraint(:region_id)`) — same pattern as `notification_preference_changeset/2`.

### Callers (grep across lib/ and test/)
None exist yet — zero call sites for `region_locked?` or `change_region` anywhere in the codebase. The only place a region-change UI action is *expected* is `lib/cuevolution_web/live/player/profile_settings_live.ex` / `.html.heex` (per spec 003's plan.md line 63: `profile_settings_live.ex # Notification preference + region change (when unlocked)`). Confirmed: `profile_settings_live.html.heex` lines 36-41 currently render a **static, unconditional** "EDITABLE" badge and the message *"You can still change your region — you haven't played a match yet."* — no `region_locked?/1` call, no `phx-click`, no form. This is the exact spot to wire up: badge/message need to become conditional on `Accounts.region_locked?(@current_player)`, and a region-select control + `handle_event("change_region", %{"region_id" => id}, socket)` calling `Accounts.change_region/2` needs to be added, mirroring the existing `set_notification_preference` handler at `profile_settings_live.ex:26-38`.

### What `Competitions` needs to expose
A query function such as `Competitions.player_has_match_result?(player_id)` — per spec 003's resolved ambiguity (line 60), this must check for existence of a `Competitions.MatchResult` row (from `T086`'s `match_results` table, which per T086 has FKs presumably to `fixture_id`; the player linkage is indirect through `Fixture` → participants or through `MatchFrame`/`CuevoPointsEntry` `participant` refs per T088) — **not** `Fixture` existence. The exact join path depends on how `MatchResult`/`Fixture` reference players (Individual category) vs. teams (Team category) — this needs confirming once `Competitions`' schema (T086-T088) is built, since a player's match participation may be resolvable only via `Fixture` → `MatchResult`, filtered to fixtures where that player was a participant.

---

## 2. `Cuevolution.Accounts.anonymize_player/2` (T032)

### Current state
Does not exist. `Player.anonymized_at` (schema field, `lib/cuevolution/accounts/player.ex:32`) is already present and already **read** (never written) in three places:
- `lib/cuevolution/accounts.ex:235` — `list_players_filtered/1`'s category query filters `is_nil(p.anonymized_at)`
- `lib/cuevolution_web/live/admin/admin_dashboard_live.ex:99` — `active_players_query` filters `is_nil(p.anonymized_at)`
- `lib/cuevolution_web/live/admin/player_directory_live.ex:90` — surfaces `anonymized: !is_nil(player.anonymized_at)` to the directory row
- `lib/cuevolution_web/live/admin/player_detail_live.html.heex:19-21` — renders an "ANONYMIZED" badge `:if={@player.anonymized_at}`

No UI affordance to *trigger* anonymization exists anywhere — grepped `player_detail_live.ex`/`.html.heex` for "anonymize"/TODO: zero hits beyond the read-only badge above. `player_detail_live.ex` (37 lines) currently only does a `mount/2` (loads player + last 10 notifications) and a private `player_fields/1` helper — no `handle_event` clauses at all yet.

### Insertion point
New function in `lib/cuevolution/accounts.ex`, alongside `log_admin_action/4` (lines 69-80) since it must call it. Needs a new `Player` changeset (`anonymize_changeset/1` or similar) that nils/placeholders PII fields (`first_name`, `last_name`, `email`, `mobile_number`, `profile_picture_path`, `location`; `username` → placeholder like `"Former Player #<id-fragment>"`) and sets `anonymized_at: DateTime.utc_now()`. Suggested signature per T032/FR-004..FR-008:

```elixir
def anonymize_player(%Player{} = player, %Admin{} = admin) do
  # 1. query Competitions for captaincy + pending-fixture warning (FR-007) — surfaced to caller, not silently checked
  # 2. Multi: update player via anonymize changeset, reject if already anonymized/login should already be rejected post-anonymize
  # 3. log_admin_action(:anonymize_player, admin, player, prior_value: ..., new_value: ...)
end
```
Given FR-007 requires the admin to be **warned and explicitly confirm** before anonymizing a captain/pending-fixture player, this likely needs to be split into two functions: a check (e.g. `Accounts.anonymize_warnings(player)` returning `[:captain, :pending_fixtures]` or `[]`) called by the LiveView to render a confirm dialog, and the actual `anonymize_player/2` mutation — mirroring how `T061`'s admin-override pattern logs via `log_admin_action/4`. The exact two-arg signature (`anonymize_player/2`) in tasks.md is ambiguous whether the 2nd arg is the acting `Admin` or an `opts` — given `log_admin_action/4`'s existing `(action_type, admin, entity, opts)` shape and every other admin-audited context function pattern, `anonymize_player(player, admin)` is the most consistent read.

### Callers
None exist yet (zero hits for `anonymize_player` in `lib/` or `test/`). Expected caller: a new `handle_event("anonymize", _params, socket)` in `lib/cuevolution_web/live/admin/player_detail_live.ex`, plus a new "Anonymize" button in `player_detail_live.html.heex` (currently absent — the card ending around line 34-36 of the heex, right after `player_fields/1`'s grid, is the natural spot, consistent with where the ANONYMIZED badge already renders conditionally at the top of the page, line 19-21).

### What `Competitions` needs to expose
Two query needs for the FR-007 warning:
1. Captaincy check — this is actually a `Teams` concern, not `Competitions` (`Team.captain_id == player.id`, already queryable via existing `Teams` context / `Repo.get_by(Team, captain_id: player.id)`) — no new `Competitions` dependency here, just a same-context/`Teams` cross-context call.
2. Pending/unplayed-fixture check — this **is** a `Competitions` dependency: something like `Competitions.player_has_pending_fixtures?(player_id)` (or team-level equivalent, since Team-category fixtures involve the player's team, not the player directly) querying `Fixture` rows without a corresponding `MatchResult` that the player (individually or via team) is a participant in. Exact query depends on T077-T085 (fixtures, spec 007) schema, not yet built.

---

## 3. `Cuevolution.Teams.add_player_to_roster/2` roster-freeze clause (T058) + `roster_locked_at` origin

### Current state
Function **exists** at `lib/cuevolution/teams.ex:68-91`:
```elixir
def add_player_to_roster(%Team{} = team, %Player{} = player) do
  Multi.new()
  |> Multi.run(:check_capacity, fn repo, _changes -> ... end)
  |> Multi.update_all(:claim_player, fn _changes -> claim_query(player.id, team.id) end, [])
  |> Multi.run(:verify_claim, fn _repo, %{claim_player: {count, _}} -> ... end)
  |> Repo.transaction()
  |> case do
    {:ok, _changes} -> ... {:ok, updated_player}
    {:error, :check_capacity, :roster_full, _changes} -> {:error, :roster_full}
    {:error, :verify_claim, :already_on_a_team, _changes} -> {:error, :already_on_a_team}
  end
end
```
Its docstring (lines 65-67) already flags the gap explicitly: *"The roster-freeze clause (FR-008, once `team.roster_locked_at` is set) is deferred until `Competitions.MatchResult` exists — not implemented yet."*

`Team.roster_locked_at` (schema column, `lib/cuevolution/teams/team.ex:10`) exists but is never set anywhere in the codebase (grepped `roster_locked_at` across `lib/`+`test/`: only the schema field decl and the docstring comment above reference it — zero writes, zero reads in query logic).

### Exact insertion point for the freeze check
Inside the `Multi.new() |> ...` pipeline in `add_player_to_roster/2` (`lib/cuevolution/teams.ex:69`), a new `Multi.run(:check_not_frozen, fn _repo, _changes -> if team.roster_locked_at, do: {:error, :roster_frozen}, else: {:ok, nil} end)` step needs to be added (likely as the very first step, before `:check_capacity`), plus a new case clause `{:error, :check_not_frozen, :roster_frozen, _changes} -> {:error, :roster_frozen}` in the final `case`. Spec 005 FR-008 says this applies to **both add and remove** — `remove_player_from_roster/2` (`lib/cuevolution/teams.ex:124-132`) currently has **no** such guard either and will need the identical check (that function isn't in T058's scope per tasks.md, but FR-008's text says "adding or removing," so it's a related gap worth flagging — tasks.md doesn't have an explicit T-number for the remove-side freeze, only T058 covers add).

### Callers of `add_player_to_roster/2`
- `lib/cuevolution_web/live/player/team_dashboard_live.ex:36` — `case Teams.add_player_to_roster(socket.assigns.team, player) do` (the captain-facing "add player" UI action — this is where a `{:error, :roster_frozen}` clause will need a new flash/error branch)
- `test/cuevolution/teams_test.exs:48,68,79,83,93,104,117,128,141,161,170` — extensive existing coverage of capacity/already-on-a-team cases; grepped for `roster_locked`/`freeze`/`override_roster` — **zero pending/skipped tests found**, so T058's freeze clause has no test scaffolding waiting for it; new tests must be written from scratch.
- `test/cuevolution/teams_concurrency_test.exs:33` — the concurrent-add race test (`Task.async_stream`), unrelated to freeze.
- `test/cuevolution_web/live/team_dashboard_live_test.exs:63,78` — LiveView-level setup calls, not testing the freeze clause itself.

### What sets `roster_locked_at` in the first place
Per spec 005's Edge Cases (line 68) and Assumptions (line 104): *"A roster freeze now applies once the team's first `Match Result` (spec 008) exists"* — and FR-008 explicitly: *"once the team has at least one recorded `Match Result` (spec 008)."* This is **not** stage-begin or fixture-entry — it is specifically the first `Competitions.MatchResult` row referencing a fixture the team participated in (Team category). Per tasks.md T090, `Competitions.record_result/2` is the function that creates `MatchResult` rows (T086 defines the `match_results` table with a unique index on `fixture_id`). So the natural place to SET `roster_locked_at` is inside `Competitions.record_result/2` (`lib/cuevolution/competitions.ex`, not yet created) — after inserting the `MatchResult`, if the fixture's category is Team and the involved team(s) don't yet have `roster_locked_at` set, update it via `Teams.lock_roster/1` (a new function `Teams` would need to expose, e.g. `Repo.update_all(from(t in Team, where: t.id in ^team_ids and is_nil(t.roster_locked_at)), set: [roster_locked_at: DateTime.utc_now()])`). This makes `Competitions` the caller into `Teams`, not the reverse — consistent with `Teams.add_player_to_roster/2`'s freeze check only needing to *read* `team.roster_locked_at` (already in-memory on the passed-in `%Team{}` struct, no new `Competitions` query needed at read time — the dependency is entirely on `Competitions` being the thing that *writes* the column).

### `Teams.override_roster_change/3` (T061, also blocked)
Does not exist yet either (zero hits). Per tasks.md: *"admin override past the freeze, FR-009) — logs via `Accounts.log_admin_action/4`."* No callers found. This is the FR-009 counterpart that lets an admin add/remove past the freeze — needs to bypass the same `:check_not_frozen` Multi step (or take an `override?: true` opt) and always call `Accounts.log_admin_action/4` regardless of outcome.

---

## Summary table

| Function | Exists now? | File | New dependency on `Competitions` |
|---|---|---|---|
| `Accounts.region_locked?/1` | No | `lib/cuevolution/accounts.ex` | `Competitions.player_has_match_result?/1` (or equivalent MatchResult-existence-for-player query) |
| `Accounts.change_region/2` | No | `lib/cuevolution/accounts.ex` + new `Player.region_changeset/2` | Indirect, via `region_locked?/1` |
| `Accounts.anonymize_player/2` | No | `lib/cuevolution/accounts.ex` + new `Player.anonymize_changeset/1` | `Competitions.player_has_pending_fixtures?/1` (FR-007 warning); captaincy check is a `Teams`, not `Competitions`, dependency |
| `Teams.add_player_to_roster/2` freeze clause | Function exists, freeze clause missing | `lib/cuevolution/teams.ex:68-91` | None to *read* (reads `team.roster_locked_at` already in struct); `Competitions.record_result/2` (not yet built) is what must *write* `roster_locked_at` via a new `Teams.lock_roster/1` |
| `Teams.override_roster_change/3` | No | `lib/cuevolution/teams.ex` | Same as above — needs to bypass the freeze check |

No pending/skipped tests exist in `test/cuevolution/accounts_test.exs` or `test/cuevolution/teams_test.exs`/`teams_concurrency_test.exs` for any of these three — all test coverage for the blocked functionality will need to be written new once `Competitions.MatchResult` lands.
