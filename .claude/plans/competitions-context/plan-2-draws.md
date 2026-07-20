# Plan: Competitions Draws (Rounds, Fixtures, FixtureEntryLive)

**Status**: COMPLETE
**Created**: 2026-07-14
**Detail Level**: comprehensive
**Input**: project-scope/tasks.md "Context 5: Competitions" T077–T085, specs 007-draws-management
**Depends on**: Plan 1 (competitions-foundation) — needs `StageParticipation`
**Unblocks**: Plan 3 (needs `Fixture` for `MatchResult.fixture_id`), makes `AdminDrawsLive`/player `FixturesLive` real

## Summary

Add `Round`/`Fixture` to `Cuevolution.Competitions`, wire the existing (already-built) participant/venue live-search UI on `AdminDrawsLive` to a real batch-entry backend, and dispatch `fixture_assignment` notifications post-commit. Rewires two already-existing but non-functional pages: `AdminDrawsLive` (→ `FixtureEntryLive`) and player-facing `FixturesLive`.

## Scope

**In Scope:**

- `rounds`, `fixtures` tables (order-independent duplicate-pairing guard, same-category/same-stage cross-check)
- `Competitions.enter_fixtures/2` (batch, partial-success), `update_fixture/2` (edit pre-result, locked post-result), UTC/EAT display helper
- Post-commit `fixture_assignment` notification dispatch to both participants (team fixtures fan out per roster member)
- Rewire `AdminDrawsLive` → real save; rewire player `FixturesLive`

**Out of Scope:**

- Match results/points (Plan 3 — `Fixture.result_id` stays a plain nullable FK until then)
- Standings (Plan 4)

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Fixture participant FK target | `stage_participations.id` (not `players.id`/`teams.id` directly) | Reuses Plan 1's union type — avoids re-deriving polymorphism (Iron Law #3); FR-006's same-category/same-stage check becomes a trivial struct comparison |
| Duplicate-pairing guard | `unique_index` with `least(participant_a_id, participant_b_id)` / `greatest(...)` expression columns | Order-independent (FR-007), same functional-index mechanism already used for `venues_region_lower_name_active_index`; no raw SQL needed |
| Batch entry semantics | Per-row `Ecto.Multi` steps, not all-or-nothing | FR-009: a batch with 1 invalid row among N commits the valid rows and reports the specific error |
| Notification dispatch timing | Post-commit, not inside the `Ecto.Multi` transaction | Don't hold a DB connection open across a network-bound call (T082's explicit requirement); matches `Accounts.register_player/1`'s existing rescue-and-log-don't-crash pattern |
| Combobox UI | Reuse existing `AdminComponents.field_search/1` | Already built and working (participant/venue live-search on the Draws page) — do not rebuild |

## Data Model

```elixir
# rounds
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :group_id, references(:groups, on_delete: :delete_all)   # nullable — knockout rounds may not have one
add :name, :string, null: false

# fixtures
add :round_id, references(:rounds, on_delete: :delete_all), null: false
add :participant_a_id, references(:stage_participations, on_delete: :restrict), null: false
add :participant_b_id, references(:stage_participations, on_delete: :restrict), null: false
add :venue_id, references(:venues, on_delete: :restrict), null: false
add :scheduled_at, :utc_datetime, null: false
add :result_id, :binary_id   # forward ref — real FK added in Plan 3's create_match_results migration
# unique_index [:round_id, "least(participant_a_id, participant_b_id)", "greatest(participant_a_id, participant_b_id)"]
# constraint participants_must_differ
```

Full migration code in `research/ecto-schema.md` "Migration 5".

## Module Structure

- `lib/cuevolution/competitions/round.ex`, `fixture.ex` (new files in the existing `Cuevolution.Competitions` module tree from Plan 1)
- `lib/cuevolution_web/live/admin/admin_draws_live.ex` (+`.html.heex`) — **rewire in place**, do not create a new module (see Phase 3)
- `lib/cuevolution_web/live/player/fixtures_live.ex` (+`.html.heex`) — **rewire in place**

## Phase 1: Migration & Schema [COMPLETE]

- [x] [P1-T1][ecto] `create_rounds_and_fixtures` migration and schemas — `Fixture.result_id` shipped as a plain `field` (not `belongs_to`) since Ecto validates association targets at compile time and `MatchResult` doesn't exist until Plan 3; upgrade to a real `belongs_to` there
- [x] [P1-T2][direct] `round_factory/0`, `fixture_factory/0`

## Phase 2: Context Functions [COMPLETE]

- [x] [P2-T1][ecto] `Competitions.enter_fixtures/2` — per-row independent `Ecto.Multi`+`Repo.transaction`, resolves player/team-kind selections to `StageParticipation` via `resolve_participant/5`, partial success confirmed by test
- [x] [P2-T2][ecto] `Competitions.update_fixture/2` + `fixture_time_in_eat/1` (EAT = fixed UTC+3, no DST/tzdata dependency)
- [x] [P2-T3][direct] Post-commit `dispatch_fixture_assignment/3` — team-category fan-out to full roster confirmed by test (3 notifications for a 2-player team + 1 opponent)
- Also added (small, natural extensions not separately tasked): `list_rounds_for_stage/1`, `create_round/1`, `list_fixtures_for_round/1`, `upcoming_fixtures_for_player/1`, public `participant_name/1` (promoted from private, reused by the LiveView template)

## Phase 3: LiveViews [COMPLETE]

- [x] [P3-T1][liveview] Rewired `AdminDrawsLive` → real fixture entry — kept all existing search/select code and event names untouched; added stage tabs, round picker + inline round creation, per-row inline error display, `stream/3`-backed "Already entered" list. **Found and fixed two real bugs**: (1) a bare `<select phx-change=...>` outside a `<form>` throws at the JS layer — wrapped the round picker in a plain `<form>`; (2) the freshly-inserted fixture returned by `enter_fixtures/2` wasn't preloaded with participants/venue, crashing the template on the first stream insert — fixed by preloading before returning `{:ok, fixture}`
- [x] [P3-T2][liveview] Rewired player `FixturesLive` — `upcoming_fixtures/1` now real; `recent_results/1` stays `[]` (honest — `MatchResult` doesn't exist until Plan 3)

## Phase 4: Tests & Verification [COMPLETE]

- [x] [P4-T1][test] 20 new `Competitions` tests (rounds, `Fixture.changeset/3` cross-check, `enter_fixtures/2` batch/duplicate/rematch/partial-failure/team-fan-out, `update_fixture/2`, `fixture_time_in_eat/1`) — all passing
- [x] [P4-T2][test] `admin_draws_live_test.exs` extended to 8 tests (real save creates a fixture, missing-round error, partial-failure-with-inline-error-and-good-row-still-saves) — all 4 original search/select tests still pass unchanged. `fixtures_live_test.exs` extended to 5 tests including one real upcoming-fixture assertion
- [x] [P4-T3][direct] Full verification: format/credo/compile clean, **263 tests, 0 failures** (up from 246 after Plan 1) — plus a real-browser pass (Playwright) confirming round creation, participant/venue search-select, save, and the entered-fixtures stream all work end-to-end with correct EAT→UTC time conversion

## Files to Follow as Patterns

- `lib/cuevolution_web/live/admin/admin_draws_live.ex` (+`.html.heex`) — the file being rewired; its search/select code is the reference for keeping vs. replacing
- `lib/cuevolution_web/components/admin_components.ex`'s `field_search/1` — already-built combobox, reuse don't rebuild
- `lib/cuevolution/notifications.ex` — `dispatch/3` allowlist, rescue/log/`:ok` caller pattern (see `Teams.dispatch_team_assignment/2`)
- `test/cuevolution_web/live/admin_draws_live_test.exs` — existing test structure to extend

## Patterns to Follow

- `Ecto.Multi` per-row batch pattern (new — no exact precedent in this codebase yet, closest is `Teams.create_team/2`'s single-row Multi)
- Post-commit dispatch, never inside the write transaction

## Session Handoff

- **Discovery**: `AdminDrawsLive` already has real, tested participant/venue search-and-select (built in a prior session) — this plan is scoped to wiring "save" and round selection to real persistence, NOT rebuilding the search UI. A prior bug (sharing `phx-keydown`+`phx-key` and `phx-keyup` on the same element silently starves one binding — see the component's moduledoc) was already found and fixed; don't reintroduce that pattern elsewhere in this LiveView.
- **Decisions**: Team-category fixture notifications fan out per roster member since `Notifications.dispatch/3` is player-only.
- **Warnings**: `Fixture.changeset/3`'s 3rd arg (preloaded participants) means callers must preload before building the changeset — don't let `enter_fixtures/2` accidentally N+1 this per row; preload all involved `StageParticipation`s in one query before the `Multi`.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Per-row `Ecto.Multi` with partial success is unusual — easy to accidentally roll back the whole batch on one bad row | Explicit test asserting N-1 rows commit when row N is invalid; don't wrap the whole batch in a single `Multi.insert` per row without per-row error capture |
| Post-commit notification dispatch failing silently swallows real delivery bugs | Rescue block still logs via `Logger.error` (matches existing pattern) — verify log output in tests via `ExUnit.CaptureLog` if dispatch failure paths are tested |
| Round picker UX (new) doesn't match the rest of the already-built row UI | Follow the disabled-select's existing visual chrome, just make it functional — don't redesign |

## Verification Checklist

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix format --check-formatted` passes
- [ ] `mix credo --strict` passes
- [ ] `mix test` passes (full suite, no regressions — especially existing `admin_draws_live_test.exs`'s 5 search/select tests)
- [ ] Batch fixture entry with a deliberately-bad row commits the good rows and reports the bad one
- [ ] A saved fixture triggers exactly one notification dispatch per participant (verify via Oban job assertions, not just "no crash")
