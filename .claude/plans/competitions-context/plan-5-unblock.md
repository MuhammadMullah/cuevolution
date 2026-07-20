# Plan: Unblock Accounts & Teams (Region Lock, Anonymize, Roster Freeze)

**Status**: COMPLETE
**Created**: 2026-07-14
**Detail Level**: more
**Input**: project-scope/tasks.md T027, T028, T032, T058, T061; specs 003-player-registration (US3/FR-008), 005-team-management (FR-008/FR-009), 010-admin-directory-data-privacy (US2/FR-004..FR-008)
**Depends on**: Plan 2 (needs `Fixture` for pending-fixture checks), Plan 3 (needs `MatchResult` for region-lock + roster-freeze checks)
**Unblocks**: nothing further — this is the final plan, closes out every "⚠️ blocked on Competitions" comment in the existing codebase
**Completed 2026-07-18**: `override_roster_change/3` shipped as `override_roster_change/4` (`action, team, player, admin`) instead — the plan's arity-3 sketch didn't have room for both an action (`:add`/`:remove`) and an admin arg; FR-009's actual text covers overriding both directions, not just add, so the action parameter was added rather than shipping an add-only override. `add_player_to_roster/2` and `remove_player_from_roster/2` both grew a trailing `opts \\ []` (arity 3) for the same `override?: true` bypass, backward-compatible with every existing 2-arg call site. All other functions match the plan as written. `grep -rn "blocked on Competitions" lib/` confirmed clean.

## Summary

Three pieces of functionality in `Accounts`/`Teams` have been sitting deferred since those contexts were first built, each with an explicit `⚠️ blocked on Competitions` comment already in the code: region-change locking, player anonymization's pending-fixture warning, and team roster-freeze. This plan implements all three now that `Competitions.MatchResult`/`Fixture` exist.

## Scope

**In Scope:**

- `Accounts.region_locked?/1` + `change_region/2` — wire the already-existing-but-unconditional "EDITABLE" badge in `ProfileSettingsLive`
- `Accounts.anonymize_player/2` — including the FR-007 captain/pending-fixture warning; add the (currently entirely absent) anonymize UI to `PlayerDetailLive`
- `Teams.add_player_to_roster/2`'s roster-freeze clause + the same guard on `remove_player_from_roster/2` (FR-008 covers both, only `add` has a task number)
- `Teams.override_roster_change/3` (T061, admin override past the freeze)

**Out of Scope:**

- Anything already covered by Plans 1–4 (this plan only touches `Accounts`/`Teams`, reading from `Competitions`, never writing to it — except Plan 3 already added the one write, `Teams.lock_roster/1`, called from `Competitions.record_result/2`)

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Region lock check | `Competitions.player_has_match_result?(player_id)` — new query, not `Fixture` existence | Spec 003's explicitly resolved ambiguity: locked by *played* matches, not scheduled fixtures |
| Anonymize warning split | Two functions: `anonymize_warnings/1` (check, called by LiveView to render a confirm dialog) + `anonymize_player/2` (the actual mutation) | FR-007 requires the admin to be warned and explicitly confirm before anonymizing a captain/pending-fixture player — can't be a single blocking call |
| Anonymize function signature | `anonymize_player(player, admin)` | Matches every other admin-audited context function's `(entity, admin, ...)` shape feeding `log_admin_action/4` |
| Roster-freeze read | `team.roster_locked_at` already in-struct — no new `Competitions` query needed at read time | Plan 3 already wrote this column; `Teams` just reads the field it's passed |
| Captaincy check for anonymize warning | `Teams`-only dependency, not `Competitions` | Captaincy is `Team.captain_id == player.id`, unrelated to the Competitions schema |

## Data Model

No new tables, no new columns. `Player.anonymized_at` and `Team.roster_locked_at` already exist (added speculatively in earlier migrations, unused until now).

## Module Structure

- `lib/cuevolution/accounts.ex` — add `region_locked?/1`, `change_region/2`, `anonymize_warnings/1`, `anonymize_player/2`
- `lib/cuevolution/accounts/player.ex` — add `region_changeset/2`, `anonymize_changeset/1`
- `lib/cuevolution/teams.ex` — add freeze check to `add_player_to_roster/2` + `remove_player_from_roster/2`, add `override_roster_change/3`
- `lib/cuevolution_web/live/player/profile_settings_live.ex` (+`.heex`) — wire the existing static badge
- `lib/cuevolution_web/live/admin/player_detail_live.ex` (+`.heex`) — add anonymize button/confirm flow (currently has zero `handle_event` clauses)

## Phase 1: Accounts Region Lock [COMPLETE]

- [x] [P1-T1][ecto] `Competitions.player_has_match_result?/1`
  **Implementation**: Existence check — does this player have a `MatchResult` via a `Fixture` they were a participant in (individually, or via their team for Team-category)? Exact join path depends on the final `Fixture`/`MatchResult`/`StageParticipation` shape from Plans 2–3 — confirm during implementation, not guessable in advance.
  **Locations**: `lib/cuevolution/competitions.ex`

- [x] [P1-T2][direct] `Accounts.region_locked?/1` + `change_region/2` + `Player.region_changeset/2`
  **Implementation**: `region_locked?(%Player{} = player)` delegates to `Competitions.player_has_match_result?/1`. `change_region/2` returns `{:error, :region_locked}` if locked, else updates via new `Player.region_changeset/2` (cast `[:region_id]`, `validate_required`, `foreign_key_constraint` — mirrors `notification_preference_changeset/2`'s exact shape).
  **Locations**: `lib/cuevolution/accounts.ex`, `lib/cuevolution/accounts/player.ex`

- [x] [P1-T3][liveview] Wire `ProfileSettingsLive`'s region-change UI
  **Implementation**: `profile_settings_live.html.heex:36-41` currently renders a **static, unconditional** "EDITABLE" badge and "You can still change your region — you haven't played a match yet." with no handler at all. Make the badge/message conditional on `Accounts.region_locked?(@current_player)`; add a region-select control + `handle_event("change_region", %{"region_id" => id}, socket)` calling `Accounts.change_region/2`, mirroring the existing `set_notification_preference` handler at `profile_settings_live.ex:26-38`.
  **Locations**: `lib/cuevolution_web/live/player/profile_settings_live.ex`, `profile_settings_live.html.heex`

## Phase 2: Accounts Anonymize [COMPLETE]

- [x] [P2-T1][ecto] `Competitions.player_has_pending_fixtures?/1`
  **Implementation**: Fixtures without a corresponding `MatchResult` that the player (individually, or via their team for Team-category) is a participant in.
  **Locations**: `lib/cuevolution/competitions.ex`

- [x] [P2-T2][direct] `Player.anonymize_changeset/1`, `Accounts.anonymize_warnings/1`, `Accounts.anonymize_player/2`
  **Implementation**: `anonymize_changeset/1` nils/placeholders PII fields (`first_name`, `last_name`, `email`, `mobile_number`, `profile_picture_path`, `location`; `username` → a placeholder like `"Former Player #<id-fragment>"` to keep the unique index satisfied) and sets `anonymized_at: DateTime.utc_now()`. `anonymize_warnings(%Player{})` returns `[:captain, :pending_fixtures]` or `[]` — captaincy via `Repo.get_by(Team, captain_id: player.id)` (a `Teams`-context lookup, not `Competitions`), pending-fixtures via `player_has_pending_fixtures?/1`. `anonymize_player(player, admin)` performs the mutation and calls `Accounts.log_admin_action/4` (first-time entry — prior_value/new_value pattern per the existing function's contract). Login must be rejected post-anonymize — confirm `authenticate_player/2` already fails naturally once `hashed_password`/`email` are cleared, or add an explicit guard if not.
  **Locations**: `lib/cuevolution/accounts.ex`, `lib/cuevolution/accounts/player.ex`

- [x] [P2-T3][liveview] Add anonymize UI to `PlayerDetailLive`
  **Implementation**: `player_detail_live.ex` currently has zero `handle_event` clauses. Add an "Anonymize" button (natural spot: right after the `player_fields/1` grid in the `.heex`, near where the existing conditional "ANONYMIZED" badge already renders at the top). Clicking it calls `anonymize_warnings/1`; if non-empty, show a confirm dialog listing the warnings (captain / pending fixtures) before proceeding; `handle_event("anonymize", ...)` calls `anonymize_player/2`.
  **Locations**: `lib/cuevolution_web/live/admin/player_detail_live.ex`, `player_detail_live.html.heex`

## Phase 3: Teams Roster Freeze [COMPLETE]

- [x] [P3-T1][direct] Freeze clause on `add_player_to_roster/2` + `remove_player_from_roster/2`
  **Implementation**: In `add_player_to_roster/2` (`lib/cuevolution/teams.ex:68-91`), add `Multi.run(:check_not_frozen, fn _repo, _changes -> if team.roster_locked_at, do: {:error, :roster_frozen}, else: {:ok, nil} end)` as the first step in the existing `Multi` pipeline, plus a new case clause `{:error, :check_not_frozen, :roster_frozen, _changes} -> {:error, :roster_frozen}`. `remove_player_from_roster/2` (lines 124-132, currently a plain conditional `update_all` with no `Multi`) needs the same guard — add a pre-check (`if team.roster_locked_at, do: {:error, :roster_frozen}, else: ...`) before the existing `update_all` call, per FR-008's text covering both add and remove even though tasks.md only numbered the add-side (T058).
  **Locations**: `lib/cuevolution/teams.ex`

- [x] [P3-T2][direct] `Teams.override_roster_change/3` (T061)
  **Implementation**: Admin override past the freeze (FR-009) — same underlying add/remove logic but bypasses `:check_not_frozen` (or takes an `override?: true` opt threaded through), and always calls `Accounts.log_admin_action/4` regardless of outcome, per tasks.md's description.
  **Locations**: `lib/cuevolution/teams.ex`

- [x] [P3-T3][liveview] `TeamDashboardLive` error branch
  **Implementation**: `team_dashboard_live.ex:36`'s existing `case Teams.add_player_to_roster(...)` needs a new `{:error, :roster_frozen}` clause with an appropriate flash message — currently only handles `{:error, :already_on_a_team}`/`{:error, :roster_full}`.
  **Locations**: `lib/cuevolution_web/live/player/team_dashboard_live.ex`

## Phase 4: Tests & Verification [COMPLETE]

- [x] [P4-T1][test] `Accounts` region-lock + anonymize tests
  **Implementation**: `region_locked?/1` (both "no match → unlocked" and "has match → locked" paths, per T027's own description), `change_region/2` enforcing the lock, `anonymize_warnings/1` (all four combinations of captain/not × pending-fixtures/not), `anonymize_player/2` (PII cleared, historical `match_results`/`cuevo_points_entries` untouched per FR-007, login rejected post-anonymize, admin action logged).
  **Locations**: `test/cuevolution/accounts_test.exs` (extend — currently has zero coverage for these three functions per the earlier research trace)

- [x] [P4-T2][test] `Teams` roster-freeze + override tests
  **Implementation**: `add_player_to_roster/2` rejects when frozen, succeeds when not; `remove_player_from_roster/2` same; `override_roster_change/3` bypasses the freeze and always logs.
  **Locations**: `test/cuevolution/teams_test.exs` (extend — currently zero coverage for these, confirmed by the integration-points research trace)

- [x] [P4-T3][direct] Full verification run
  **Implementation**: `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test` — confirm zero regressions in the extensive existing `accounts_test.exs`/`teams_test.exs`/`teams_concurrency_test.exs` coverage (per the research trace, these files have substantial existing tests at lines 48-170 that must keep passing).

## Files to Follow as Patterns

- `lib/cuevolution/accounts.ex`'s `notification_preference_changeset/2` — template for `region_changeset/2`
- `lib/cuevolution/accounts.ex`'s `log_admin_action/4` — used by both `anonymize_player/2` and `override_roster_change/3`
- `lib/cuevolution/teams.ex`'s `remove_player_from_roster/2` — plain conditional `update_all`, template for the freeze pre-check
- `lib/cuevolution_web/live/player/profile_settings_live.ex`'s existing `set_notification_preference` handler — template for `change_region`'s handler shape

## Patterns to Follow

- Every admin-triggered mutation logs via `log_admin_action/4`
- Warnings are surfaced and require explicit confirmation, never silently bypassed

## Session Handoff

- **Discovery**: All three deferred functions/clauses were already explicitly documented as blocked at the exact insertion points (`⚠️` comments already in `Teams.create_team/2`'s docstring, `Teams.add_player_to_roster/2`'s docstring) — this plan closes every one of them, and after this plan there should be zero remaining `⚠️ blocked on Competitions` comments in the codebase (grep to confirm as a final check).
- **Decisions**: `anonymize_player/2`'s signature `(player, admin)` was ambiguous in tasks.md (2-arg, unclear if 2nd arg is `Admin` or `opts`) — resolved to `Admin` for consistency with every other admin-audited function.
- **Warnings**: `remove_player_from_roster/2`'s freeze guard is *not* in tasks.md's numbered task list (only `add_player_to_roster/2`'s is, as T058) but IS required by FR-008's actual text — don't skip it just because it lacks a T-number.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Anonymize's PII-clearing changeset accidentally cascades to delete historical match/points data | FR-007 explicit requirement: historical `match_results`/`cuevo_points_entries` stay untouched — verify via a test that inserts a match result for a player, anonymizes them, then asserts the match result row still exists with its original `winner_participation_id` intact |
| `override_roster_change/3`'s bypass logic accidentally also bypasses the roster-size cap (5-8) | Only bypass `:check_not_frozen` — capacity/duplicate-membership checks stay active even for admin overrides, since those are correctness invariants, not the freeze policy |
| Region-change UI ships without the lock actually being enforced (badge says locked but form still submits) | `change_region/2` itself returns `{:error, :region_locked}` regardless of what the UI shows — the context function is the real guard, the UI is just presentation; test the context function directly, not just the LiveView |

## Verification Checklist

- [x] `mix compile --warnings-as-errors` passes
- [x] `mix format --check-formatted` passes
- [x] `mix credo --strict` passes
- [x] `mix test` passes (full suite, no regressions)
- [x] `grep -rn "blocked on Competitions" lib/` returns nothing (every deferral closed)
- [x] A player with a recorded match result cannot change region via `change_region/2` even if the UI is bypassed (context-level test, not just LiveView-level)
- [x] Anonymizing a team captain surfaces the captaincy warning before proceeding
