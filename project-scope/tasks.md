# Cuevolution MVP — Task List (by Phoenix Context)

**Created**: 2026-07-08
**Source**: `specs/001`–`010`, `reviews/system-design-review.md` (all findings already applied to specs)
**Organization**: By Phoenix context (`Accounts`, `Notifications`, `Venues`, `Teams`, `Competitions`), per request — see **Suggested Build Order** below for why "per context" doesn't mean "finish one context, then start the next."

---

## How to use this document

- **T-ID**: sequential across the whole document, stable — reference tasks by ID in commits/PRs.
- **[P]**: can be done in parallel with other [P] tasks in the same block (different files, no dependency between them).
- **[Test→Impl]**: a TDD pair. Write the test first, run it, watch it fail for the *right* reason (not a compile error), then write the minimum implementation to pass it. Do not write both in one commit without seeing the red state — that's not negotiable per your direction.
- **No styling tasks are listed.** Every LiveView/controller task means: real routes, real `mount`/`handle_event`, real forms bound to real changesets, plain unstyled HTML elements. The design system (`design/design-system.md`) gets applied in a later pass once you're ready for it — until then, "done" for a UI task means *functionally correct*, not *pretty*.

### Definition of Done (applies to every task)

1. Idiomatic Elixir/Phoenix — passes `mix format --check-formatted` and `mix credo --strict` with no new warnings.
2. Tests written first, observed failing, then made to pass (TDD). No task is done with failing or skipped tests.
3. `mix test` green for the whole suite, not just the new tests (no regressions).
4. No compiler warnings introduced (`mix compile --warnings-as-errors` clean).

### Testing stack

- **ExUnit** for everything.
- **ExMachina** for factories (`test/support/factory.ex`, one function per schema, sequenced unique fields via `sequence/2`).
- **Mox** for the one real external-boundary behaviour in this system (`Notifications.SmsAdapter`) — everything else is real Ecto/Postgres against the sandboxed test DB, not mocked, since the whole point of this stack is that Ecto/Postgres integration bugs are the ones worth catching.
- **`Ecto.Adapters.SQL.Sandbox`** in `:manual` or `:auto` mode as appropriate; async: true wherever a test doesn't share global state (Oban jobs, PubSub) — most context-layer tests should be async.

### Performance principles (apply throughout, not a separate pass at the end)

- Every migration that adds a foreign key or a column used in a `WHERE`/`ORDER BY` adds its index **in the same migration** — index-later is how production tables end up locked for a rebuild.
- Uniqueness and cardinality invariants (one team per player, one result per fixture, capacity limits, no duplicate same-round fixture) are enforced by a **database constraint**, not just an `Ecto.Changeset` validation — the changeset gives a friendly error, the constraint is what actually guarantees correctness under concurrency. Every such task has a concurrency test proving the constraint (not the changeset) is what blocks the second writer.
- Computed values that must never drift (Cuevo Points totals, team eligibility, region-lock status) are **always queried live**, never cached in a column that can go stale — this is a repeated, deliberate pattern across this codebase, not an oversight to "optimize" later.
- Any table with an uncapped row count (standings, admin player/team directory) uses `Phoenix.LiveView.stream/3` from the first implementation, not assigns — retrofitting this later means re-touching every event handler.
- `EXPLAIN ANALYZE` checks are explicit tasks, not an afterthought — see the "Performance notes" block closing each context section.

---

## Suggested Build Order

The per-context task list below is complete and self-contained *within* each context, but a few tasks in `Accounts` and `Teams` read data owned by `Competitions` (the region-lock check, the roster-freeze check, the anonymize action's "pending fixtures" warning). You cannot implement those specific tasks before `Competitions`' `match_results` table exists. Recommended pass order:

1. **Phase 0** — project setup.
2. **Accounts** — everything except T027, T028, T032 (flagged inline below as blocked).
3. **Notifications** — needed by Accounts' registration-confirmation call.
4. **Venues** — needed by Accounts' player-venue FK and later by Competitions' fixtures.
5. **Teams** — everything except the roster-freeze clause of T058 and all of T061 (flagged inline).
6. **Competitions** — full build, in its internal sub-phase order (stages → groups → fixtures → results/points → standings).
7. **Back to Accounts**: T027, T028, T032.
8. **Back to Teams**: T058's freeze clause, T061.

This isn't a workaround — it's the honest shape of the dependency graph. Two contexts (`Accounts`, `Teams`) each have one small island of functionality that can't exist until `Competitions` does.

---

## Phase 0 — Project Setup (cross-cutting, before any context)

- **T001** [P] `mix phx.new cuevolution --live --database postgres`. Confirm Elixir 1.17+/OTP 27+, Phoenix 1.8.
- **T002** [P] Add core deps to `mix.exs`: `bcrypt_elixir`, `oban`, `swoosh`, `{:ex_machina, "~> 2.7", only: :test}`, `{:mox, "~> 1.1", only: :test}`, `credo`, `dialyxir` (dev/test), `sobelow` (dev). `mix deps.get`.
- **T003** Configure test DB (`mix ecto.create`, `mix ecto.migrate` in `MIX_ENV=test`), `Ecto.Adapters.SQL.Sandbox` wired in `test/support/data_case.ex` and `conn_case.ex`.
- **T004** [P] `test/support/factory.ex` skeleton: `use ExMachina.Ecto, repo: Cuevolution.Repo`; wire `import Cuevolution.Factory` into `data_case.ex`/`conn_case.ex`.
- **T005** [P] `test/support/mocks.ex`: `Mox.defmock(Cuevolution.Notifications.SmsAdapterMock, for: Cuevolution.Notifications.SmsAdapter)` (placeholder until the behaviour exists in T038 — create this task as a stub reference, fill in once T038 lands).
- **T006** Oban added to the supervision tree (`application.ex`), `:notifications` queue configured, `config/test.exs` sets `Oban.Testing, repo: Cuevolution.Repo` with `testing: :manual`.
- **T007** [P] `config/runtime.exs`: DB pool size via `POOL_SIZE` env var; `config/test.exs`: `pool_size: System.schedulers_online() * 2` for parallel async test throughput.
- **T008** [P] Minimal `:telemetry` hook on `Cuevolution.Repo` query events (even just a dev-log of slow queries >50ms) — groundwork for NFR-9.2, cheap to add now, expensive to retrofit.
- **T009** `mix.exs` aliases: `"test.ci": ["format --check-formatted", "credo --strict", "test"]`.

---

## Context 1: Accounts

*Owns: `Admin`, `Player`, `Region`. Satisfies specs 001, 003, and the `Accounts` half of 010.*

### 1.1 Migrations

- **T010** [P] `create_regions` — seed the 8 fixed regions as data in the same migration (NFR-2.1: data, not hardcoded). Unique index on `slug`.
- **T011** [P] `create_admins` (unique index on `email`), `create_admin_tokens` (indexed `token`+`context`), `create_admin_action_logs` (indexed `admin_id`, indexed `inserted_at` for audit browsing, `jsonb` `prior_value`/`new_value`, `action_type`, `entity_type`/`entity_id`).
- **T012** [P] `create_players` — full field set (spec 003): `region_id` FK indexed, `team_id` FK indexed nullable, unique index on `lower(username)`, unique index on `email`, `mobile_number` (E.164, normalized before insert), `gender` constrained to `male`/`female` (FR-014), `anonymized_at` nullable (spec 010), `profile_picture_path`. **Note**: `preferred_venue_id` FK is added once `Venues` exists (§3) — either sequence `Venues`' migration first, or add this FK in a follow-up migration; don't block this table on it.
- **T013** [P] `create_player_tokens` (indexed like `admin_tokens`).

### 1.2 Factories

- **T014** [P] `region_factory/0` — cycles through the 8 seeded regions, not random data.
- **T015** [P] `admin_factory/0` — valid bcrypt hash.
- **T016** [P] `player_factory/0` — all required fields, `date_of_birth` defaulting to exactly-18-or-older, sequenced unique `username`/`email`/`mobile_number`.

### 1.3 Admin authentication (spec 001)

- **T017** [Test→Impl] `Accounts.authenticate_admin/2` — correct/incorrect password, generic error (no email-vs-password leak), constant-time behavior for a non-existent email (dummy-hash comparison so timing doesn't reveal account existence).
- **T018** [Test→Impl] `Accounts.generate_admin_session_token/1` + `get_admin_by_session_token/1`.
- **T019** [Test→Impl] `AdminAuth` plug (`fetch_current_admin`, `require_admin`) + LiveView `on_mount` hook — test all three paths from spec 001 US2: anonymous → redirect, player-session → denied, admin-session → allowed.
- **T020** [Test→Impl] `AdminSessionController` login/logout — logout invalidates the session token.
- **T021** [Test→Impl] `Accounts.log_admin_action/4` (`action_type, admin, entity, opts \\ [prior_value: nil, new_value: nil]`) — first-time entries store nulls, corrections store both values.
- **T022** [P] Functional LiveViews: `AdminLoginLive`, `AdminDashboardLive`.

### 1.4 Player registration (spec 003)

- **T023** [Test→Impl] `Player` changeset — age ≥ 18 (explicit boundary test at exactly 18), case-insensitive unique username, unique email, required-fields coverage. Backed by the DB constraints from T012, not changeset-only.
- **T024** [Test→Impl] E.164 mobile normalization (FR-013) — local Kenyan format, already-E.164, invalid/unnormalizable input (rejected).
- **T025** [Test→Impl] `Accounts.register_player/1` — inserts the player, then calls `Notifications.dispatch/3` (mock the call at this context's boundary; the real cross-context integration test lives once `Notifications` exists — see §1 dependency note). Wrapped so a notification-dispatch failure never rolls back the account (spec 002: retried/logged, not blocking).
- **T026** [Test→Impl] `Accounts.update_notification_preference/2`.
- **T027** ⚠️ **Blocked on Competitions (§5c/5d)** [Test→Impl] `Accounts.region_locked?/1` — reads `Competitions.MatchResult` existence. Test both the "no match → unlocked" and "has match → locked" paths.
- **T028** ⚠️ **Blocked on Competitions** [Test→Impl] `Accounts.change_region/2` enforcing T027's lock.
- **T029** [Test→Impl] `Accounts.authenticate_player/2` + player session token functions (mirrors T017/T018, fully separate table/session — test they share zero state with admin auth).
- **T030** [P] Functional LiveViews: `RegistrationLive` (phx-change inline validation per NFR-6.2), `ProfileSettingsLive`.

### 1.5 Directory & anonymization (spec 010, Accounts half)

- **T031** [Test→Impl] `Accounts.list_players_filtered/1` (region, category, stage, username search) — index-backed (T012); test no N+1 on region/team preload.
- **T032** ⚠️ **Blocked on Competitions** [Test→Impl] `Accounts.anonymize_player/2` — PII cleared, historical `match_results`/`cuevo_points_entries` untouched, login rejected post-anonymize, admin action logged, captain/pending-fixture warning surfaced (FR-007 of spec 010).
- **T033** [P] Functional LiveViews: `PlayerDirectoryLive` (**stream-based**, uncapped row count), `PlayerDetailLive` with anonymize action.

### 1.6 Performance notes — Accounts

- **T034** `EXPLAIN ANALYZE` on username/email lookup and the filtered-directory query — confirm index usage, not sequential scans.
- **T035** Concurrent-registration test (`Task.async_stream/3`, N parallel `register_player/1` calls) — asserts no deadlocks and that only genuinely-duplicate usernames/emails fail (NFR-1.1).

---

## Context 2: Notifications

*Owns: `Notification`, the `SmsAdapter` behaviour, Oban send workers. Satisfies spec 002.*

### 2.1 Migration & factory

- **T036** [P] `create_notifications` — `player_id` (recipient), `event_type`, `source_type`/`source_id`, unique index on `idempotency_key`, `channel`, `status` (partial index on `status IN ('pending','failed')` for the admin troubleshooting view), `error_detail`, `retry_count`.
- **T037** [P] `notification_factory/0`.

### 2.2 SMS adapter

- **T038** [Test→Impl] `Cuevolution.Notifications.SmsAdapter` behaviour (`send/2`) + `StubAdapter` (always succeeds, logs). Wire the `Mox` mock from T005 against this real behaviour.

### 2.3 Dispatch core

- **T039** [Test→Impl] `Notifications.dispatch/3` payload allowlist (FR-010) — rejects any payload key shaped like `*_email`/`*_mobile_number` for another participant.
- **T040** [Test→Impl] Idempotency: `notifications` row moved to `sending` *before* the provider call (FR-009) — simulated crash-then-retry test asserts exactly one send (Mox call-count).
- **T041** [Test→Impl] `SendEmailWorker` (Oban) — asserts Swoosh mailer invoked correctly for `registration_confirmation` and `fixture_assignment`.
- **T042** [Test→Impl] `SendSmsWorker` (Oban) — same, via the `SmsAdapter` mock.
- **T043** [Test→Impl] Retry/backoff on transient failure (NFR-3.2) — adapter returns `{:error, :timeout}`, asserts Oban retries and logs each attempt, only reaches `failed` after attempts exhausted.
- **T044** [Test→Impl] "Both" preference — two independently enqueued jobs; one channel's failure doesn't block or roll back the other.

### 2.4 Admin visibility (spec 002 US3)

- **T045** [Test→Impl] `Notifications.list_delivery_log/1` (filterable by status).
- **T046** [P] Functional LiveView: `NotificationLogLive` (**stream-based**).

### 2.5 Performance notes — Notifications

- **T047** Race test: two workers processing the same logical send concurrently → the `idempotency_key` unique index allows exactly one send.
- **T048** Tune `:notifications` Oban queue concurrency to drain a full round's worth of draw notifications (~32 recipients for a 16-fixture round) without perceptible lag; document the chosen limit.

---

## Context 3: Venues

*Owns: `Venue`. Satisfies spec 004.*

- **T049** [P] `create_venues` — `name`, `region_id` indexed, composite index `(region_id, active)` (the hot query is "active venues for region X").
- **T050** [P] `venue_factory/0`.
- **T051** [Test→Impl] `Venues.list_active_for_region/1` — cross-region isolation test (spec 004 SC-001).
- **T052** [Test→Impl] `Venues.create_venue/1`, `update_venue/2`, `deactivate_venue/1` (soft delete, FR-004) — deactivated venue disappears from listings but existing player references stay valid (no FK violation).
- **T053** [Test→Impl] Duplicate venue name within a region — case-insensitive uniqueness, DB-backed partial unique index scoped to active venues.
- **T054** [P] Functional LiveView: `VenueManagementLive`.
- **Follow-up**: once this context exists, add `preferred_venue_id` FK to `players` (deferred from T012).

---

## Context 4: Teams

*Owns: `Team` (roster = `team_id` FK on `Player`, no join table — a player has at most one active team). Satisfies spec 005 and the `Teams` half of 010.*

- **T055** [P] `create_teams` (`name`, `region_id` indexed, `captain_id` indexed, `roster_locked_at` nullable for FR-008). Confirm `players.team_id` index exists (T012).
- **T056** [P] `team_factory/0` with an associated captain.
- **T057** [Test→Impl] `Teams.create_team/2` — captain assignment, region inherited from captain; a player already on a team is blocked from creating a second one, enforced by a DB-level constraint (not changeset-only).
- **T058** [Test→Impl] `Teams.add_player_to_roster/2` — **the concurrency-critical one**: two simultaneous adds of the *same* player to *different* teams → exactly one succeeds (`Ecto.Multi` + DB constraint). Max-roster-of-8 rejection. ⚠️ **Roster-freeze clause (FR-008) blocked on Competitions** — implement everything else here now, add the freeze check once `Competitions.MatchResult` exists.
- **T059** [Test→Impl] `Teams.remove_player_from_roster/2` — eligibility auto-flips below 5 (FR-005), auto-restores at 5+.
- **T060** [Test→Impl] `Teams.eligible?/1` — derived query, never a cached column.
- **T061** ⚠️ **Blocked on Competitions** [Test→Impl] `Teams.override_roster_change/3` (admin override past the freeze, FR-009) — logs via `Accounts.log_admin_action/4`.
- **T062** [P] Functional LiveViews: `TeamCreationLive`, `TeamDashboardLive`.
- **T063** Performance: `EXPLAIN` the roster-size `COUNT(*)` query against the `team_id` index.

---

## Context 5: Competitions

*Owns: `Stage`, `Group`/`GroupMembership`, `KnockoutBracket`, `StageCapacityConfig`, `StageParticipation`, `Round`, `Fixture`, `MatchResult`, `MatchFrame`, `CuevoPointsEntry`. Satisfies specs 006, 007, 008, 009 — by far the largest context, built in five internal sub-phases.*

### 5a. Stages & capacity (spec 006)

- **T064** [P] `create_stages` — seeded Grassroots/Regional/Circuit/Finals with a unique `order` column.
- **T065** [P] `create_stage_capacity_configs` — `stage_id`, `category`, `capacity_limit`, `current_count`, seeded defaults (128/64/20, 64/32/8); composite unique index `(stage_id, category)`.
- **T066** [P] `create_stage_participations` — `player_id` nullable, `team_id` nullable (CHECK: exactly one set), `region_id`, `stage_id`, `category`; composite index `(stage_id, region_id, category)`.
- **T067** [P] Factories: `stage_factory/0` (references seeded stages), `stage_capacity_config_factory/0`, `stage_participation_factory/0`.
- **T068** [Test→Impl] `Competitions.current_stage/1`.
- **T069** [Test→Impl] `Competitions.advance_to_stage/2` — **the other concurrency-critical one**: two simultaneous advancements at the last remaining capacity slot → exactly one succeeds, via the atomic `UPDATE stage_capacity_configs SET current_count = current_count + 1 WHERE current_count < capacity_limit` pattern inside `Ecto.Multi`. Open stages (Grassroots/Regional) never reject. Lowering a capacity below the current count doesn't retroactively break existing participations, only blocks new ones.
- **T070** [Test→Impl] `Competitions.capacity_config/2` + admin update (no-deploy config change, NFR-2.2).
- **T071** [P] Functional LiveViews: `StageManagementLive`, `CapacityConfigLive`.

### 5b. Groups & knockout brackets (spec 006)

> **Correction (post-Plan-1/2 feedback)**: Knockout brackets do NOT belong to Regional groups — they only exist at Circuit/Finals, one per stage+category, unrelated to groups. Grassroots groups are venue-scoped (not region-scoped); Regional groups are region-scoped; both are also category-scoped (a dimension T072 originally missed). Group size (8) and advancer-count (2-3) are admin-configurable per stage+category via a new `stage_group_configs` table, not hardcoded. See `plan-1b-format-correction.md` for the corrective migration/schema/context work layered on top of T072-T076 (already shipped) rather than rewriting them in place.

- **T072** [P] `create_groups` (`stage_id`, `region_id`, `name`), `create_group_memberships` (indexed both `group_id` and `stage_participation_id`), `create_knockout_brackets` (Regional-only, `group_id`). ~~Superseded — see correction note above.~~
- **T073** [P] Factories for groups/memberships/brackets.
- **T074** [Test→Impl] `Competitions.assign_to_group/2`.
- **T075** [Test→Impl] Grassroots grouping produces no bracket; Regional grouping produces an available, initially-empty bracket (FR-003/FR-004). ~~Superseded — Regional never produces a bracket; brackets are Circuit/Finals stage+category only, created independently of group creation.~~
- **T076** [P] Functional LiveView: `GroupManagementLive`.

### 5c. Draws / Fixtures (spec 007)

- **T077** [P] `create_rounds` (`stage_id`/`group_id`, `name`), `create_fixtures` (`round_id`, `participant_a`/`participant_b`, `venue_id` FK to §3, `scheduled_at` timestamptz [UTC], `result_id` nullable) — unique index on `(round_id, least(participant_a, participant_b), greatest(participant_a, participant_b))` (FR-007 duplicate-pairing guard, order-independent).
- **T078** [P] `round_factory/0`, `fixture_factory/0`.
- **T079** [Test→Impl] Fixture changeset — same-category/same-stage cross-check (FR-006): mismatched category rejected, mismatched stage rejected.
- **T080** [Test→Impl] `Competitions.enter_fixtures/2` (batch, FR-009) — per-row `Ecto.Multi` steps; a batch with 1 invalid row among N commits the valid rows and reports the specific error, not an all-or-nothing rollback.
- **T081** [Test→Impl] Same-round duplicate rejected; legitimate cross-round rematch accepted (FR-007, against T077's index).
- **T082** [Test→Impl] Fixture entry triggers `Notifications.dispatch/3` for both participants, opponent-name-only payload (FR-002/FR-010, Mox-asserted). Dispatch happens **post-commit**, not inside the DB transaction (don't hold a connection open across a network-bound call).
- **T083** [Test→Impl] `Competitions.update_fixture/2` — editable pre-result, locked post-result (FR-003/FR-004), triggers update notification.
- **T084** [Test→Impl] UTC-storage/EAT-display helper (FR-008) — one shared function, used everywhere a fixture time renders.
- **T085** [P] Functional LiveView: `FixtureEntryLive` (batch-capable).

### 5d. Match Results & Cuevo Points (spec 008)

- **T086** [P] `create_match_results` (unique index on `fixture_id` [FR-007 dup guard], winner ref, score, `prior_value` jsonb, `recorded_by`).
- **T087** [P] `create_match_frames` (`match_result_id` indexed, player refs, frame winner, sequence — Team-category only).
- **T088** [P] `create_cuevo_points_entries` (`participant` reference **indexed** — this is the SUM-aggregation hot path, index it deliberately — `match_result_id`, `match_frame_id` nullable, `points`, `prior_value` jsonb, `recorded_by`).
- **T089** [P] Factories: `match_result_factory/0`, `match_frame_factory/0`, `cuevo_points_entry_factory/0`.
- **T090** [Test→Impl] `Competitions.record_result/2` + duplicate-result rejection (FR-007, T086's index).
- **T091** [Test→Impl] `Competitions.correct_result/2` — captures `prior_value`, logs via `Accounts.log_admin_action/4`, surfaces the downstream-advancement warning (US4 scenario 3).
- **T092** [Test→Impl] **`StandingsCalculator`** — the FR-013 tiebreaker cascade, pure/DB-free module. This deserves the most exhaustive test coverage in the codebase since it decides who's eliminated from the tournament: one test per tiebreaker level — clean win-count ordering; wins-tied resolved by head-to-head; head-to-head-tied resolved by frame differential; frame-differential-tied resolved by total frames; fully-tied case flagged for admin resolution rather than silently guessed.
- **T093** [Test→Impl] `Competitions.group_standings/1` (wraps T092 with real query data) — applies at both Grassroots and Regional now.
- **T094** [Test→Impl] `Competitions.top_advancers/1` (renamed from `regional_top_8/1` — generalized to both Grassroots and Regional, cutoff N read from `Competitions.group_config/2`'s `advancer_count`, not hardcoded to 8) — fewer-entrants-than-N case and boundary-tie case (both via T092). Circuit/Finals get a separate `advance_knockout_round/1`-style helper instead (bracket winner advancement, not group standings — see `plan-1b-format-correction.md`/`plan-3-results-points.md`).
- **T095** [Test→Impl] `Competitions.record_points/2` + `correct_points/2` (mirrors T090/T091).
- **T096** [Test→Impl] `Competitions.points_total/1` — live `SUM`, never cached; explicit test that a correction immediately reflects with no stale double-counting (SC-006).
- **T097** [Test→Impl] Team-category frame-to-points allocation (FR-012) — per-frame-participant and/or per-team points, both modes tested.
- **T098** [P] Functional LiveViews: `ResultEntryLive`, `PointsEntryLive` (with correction affordance).

### 5e. Standings (spec 009)

- **T099** [Test→Impl] `Competitions.standings_for_category/1` — index-backed `ORDER BY points DESC` (T088), stable secondary sort by name for ties.
- **T100** [Test→Impl] PubSub broadcast on `record_points/2`/`correct_points/2` to a `"standings"` topic — a subscribed test process receives it.
- **T101** [P] Functional LiveView: `StandingsLive` — **`Phoenix.LiveView.stream/3`**, subscribed to `"standings"`.

### 5f. Performance notes — Competitions

- **T102** `EXPLAIN ANALYZE` on `group_standings/1`, `regional_top_8/1`, `standings_for_category/1` against realistic seed volumes (hundreds of Grassroots participants) — these degrade first; add indexes beyond what's listed if the plan shows sequential scans.
- **T103** Confirm T069's atomic `UPDATE` isn't a write-contention concern at the actual concurrency ceiling (single admin, at most two tabs) — deliberately not over-engineered further than that; keep T069's concurrency test as a permanent regression guard.

---

## Completion Criteria for "MVP functionality complete"

- Every FR across specs 001–010 has at least one passing test exercising it (traceable back via the T-IDs above).
- `mix test` green, `mix format --check-formatted` clean, `mix credo --strict` clean, no compiler warnings.
- All ⚠️ blocked tasks (T027, T028, T032, T058's freeze clause, T061) completed once `Competitions` exists.
- Each context's "Performance notes" tasks executed at least once against a realistically-sized seeded dataset, not just empty-table tests.
- The three "still open, by design" items from `reviews/system-design-review.md`'s Resolution Log (tiebreaker cascade, team match format, roster-freeze policy) confirmed against real league rules — if any is confirmed *different* from the default implemented here, the affected task(s) above get revisited before calling this done, since they're schema/behavior decisions, not cosmetic ones.
