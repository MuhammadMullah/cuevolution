# Plan: Competitions Results & Points (MatchResult, MatchFrame, CuevoPoints)

**Status**: COMPLETE
**Created**: 2026-07-14
**Amended**: 2026-07-18 — see `plan-1b-format-correction.md`; Regional no longer has a knockout bracket (round-robin + top-N advance, same mechanism as Grassroots→Regional now); Circuit/Finals have the knockout brackets instead. `regional_top_8/1` → `top_advancers/1`, generalized to both stages, cutoff N read from `Competitions.group_config/2` (not hardcoded 8). New: `round_winners/1` for Circuit/Finals bracket-round progression. Cuevo Points/roster-freeze mechanics are unchanged from the original plan below.
**Completed 2026-07-18**: Shipped without the dedicated `MatchFrameFormComponent`/per-frame entry UI — Team-category results are recorded at the team level (one winner, one optional aggregate score) via the same form as Individual-category. The `MatchFrame`/frame-tally data model and `StandingsCalculator` support is fully built and tested (`frame_tally/2` in `competitions.ex` reads real `match_frames` rows when present), so a follow-up admin UI can add frame-by-frame entry later without any data-model change — this was a scope call to ship the higher-priority result/points/standings-math work first.
**Detail Level**: comprehensive
**Input**: project-scope/tasks.md "Context 5: Competitions" T086–T098, specs 008-match-results-points
**Depends on**: Plan 2 (competitions-draws) — needs `Fixture`; Plan 1b (format correction) — needs `Competitions.group_config/2`, corrected `Group`/`KnockoutBracket`
**Unblocks**: Plan 4 (standings needs `CuevoPointsEntry`), Plan 5's Teams roster-freeze (needs `MatchResult` to set `roster_locked_at`)

## Summary

Add `MatchResult`, `MatchFrame`, `CuevoPointsEntry` to `Cuevolution.Competitions`, including the **standings tiebreaker cascade** — tasks.md flags this as deserving the most exhaustive test coverage in the whole codebase, since it decides tournament eliminations. Wires `Fixture.result_id`'s deferred FK. Rewires `AdminResultsLive` (currently tab-chrome-only) into real result/points entry with a correction affordance. Result entry is one function (`record_result/2`) regardless of stage — Grassroots/Regional group standings and Circuit/Finals bracket-round winners are both just reads over the same `match_results` table, filtered differently (by `group_id` vs by `round_id`).

## Scope

**In Scope:**

- `match_results`, `match_frames`, `cuevo_points_entries` tables + `Fixture.result_id`'s real FK
- `Competitions.record_result/2` + `correct_result/2` (captures `prior_value`, logs via `Accounts.log_admin_action/4`)
- `StandingsCalculator` — pure, DB-free tiebreaker cascade module (win-count → head-to-head → frame differential → total frames → flagged-for-admin on full tie)
- `group_standings/1`, `top_advancers/1` (wrap the calculator with real query data; both apply at Grassroots and Regional now, cutoff N from `Competitions.group_config/2`)
- `round_winners/1` (Circuit/Finals — winners of a completed knockout round, the pool the admin draws the next round's pairings from)
- `record_points/2`, `correct_points/2`, `points_total/1` (live SUM, never cached), team frame-to-points allocation
- Sets `Team.roster_locked_at` on first Team-category `MatchResult` (via new `Teams.lock_roster/1`)
- Rewire `AdminResultsLive` → `ResultEntryLive` (Unplayed tab) + `PointsEntryLive` (Played tab)

**Out of Scope:**

- Standings *display*/PubSub live-update (Plan 4 — this plan only builds the data layer standings reads from)
- Accounts/Teams unblocking beyond the `roster_locked_at` write (Plan 5 handles the *read* side — the freeze check itself)

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Result/points FK target | `stage_participations.id` (winner, participant) | Same union-type reuse as Plan 2's fixtures |
| Duplicate-result guard | `unique_index(:match_results, [:fixture_id])` | FR-007, DB-level not just changeset |
| Corrections | Separate `correction_changeset/2`, caller snapshots pre-update struct into `:prior_value` (jsonb) before calling | Matches spec's audit requirement — every correction must be traceable |
| Points storage | Never cached/denormalized — `points_total/1` is a live `SUM` query every time | Explicit, repeated, deliberate pattern per tasks.md's Performance Principles: "Computed values that must never drift... are always queried live" |
| Roster freeze trigger | `Competitions.record_result/2` calls a new `Teams.lock_roster/1` after inserting a Team-category `MatchResult` | Per spec 005 Assumptions: freeze applies "once the team has at least one recorded Match Result" — `Competitions` calls into `Teams`, not the reverse |
| Tiebreaker cascade | Pure function module, zero DB calls, exhaustively tested | tasks.md's own words: "this deserves the most exhaustive test coverage in the codebase since it decides who's eliminated" |

## Data Model

```elixir
# match_results
add :fixture_id, references(:fixtures, on_delete: :delete_all), null: false
add :winner_participation_id, references(:stage_participations, on_delete: :restrict), null: false
add :score, :map
add :prior_value, :map
add :recorded_by_admin_id, references(:admins, on_delete: :restrict), null: false
# unique_index [:fixture_id]

# ALSO in this migration: alter fixtures, modify :result_id, references(:match_results, on_delete: :nilify_all), from: :binary_id

# match_frames (Team category only)
add :match_result_id, references(:match_results, on_delete: :delete_all), null: false
add :home_player_id, references(:players, on_delete: :restrict), null: false
add :away_player_id, references(:players, on_delete: :restrict), null: false
add :winner_player_id, references(:players, on_delete: :restrict), null: false
add :sequence, :integer, null: false
# unique_index [:match_result_id, :sequence]
# constraint winner_must_be_home_or_away

# cuevo_points_entries
add :participant_id, references(:stage_participations, on_delete: :restrict), null: false   # indexed — SUM hot path
add :match_result_id, references(:match_results, on_delete: :restrict), null: false
add :match_frame_id, references(:match_frames, on_delete: :restrict)   # nullable, Team per-frame points
add :points, :integer, null: false
add :prior_value, :map
add :recorded_by_admin_id, references(:admins, on_delete: :restrict), null: false
```

Full migration code in `research/ecto-schema.md` "Migration 6", "Migration 7", "Migration 8".

## Module Structure

- `lib/cuevolution/competitions/match_result.ex`, `match_frame.ex`, `cuevo_points_entry.ex`
- `lib/cuevolution/competitions/standings_calculator.ex` — pure module, no `Repo` calls
- `lib/cuevolution/teams.ex` — add `lock_roster/1` (extends existing module)
- `lib/cuevolution_web/live/admin/admin_results_live.ex` (+`.html.heex`) — **rewire in place**
- `lib/cuevolution_web/live/admin/match_frame_form_component.ex` — new `LiveComponent` for Team-category frame entry (justified: real internal form state + app logic, not just DOM)

## Phase 1: Migrations & Schemas [COMPLETE]

- [x] [P1-T1][ecto] `create_match_results` migration + schema, wire `fixtures.result_id`'s deferred FK
  **Implementation**: Exact code in `research/ecto-schema.md` Migration 6. Same deferred-FK pattern already used for `players.team_id → teams` (`modify :result_id, references(...), from: :binary_id`).
  **Locations**: `priv/repo/migrations/*_create_match_results.exs`, `lib/cuevolution/competitions/match_result.ex`

- [x] [P1-T2][ecto] `create_match_frames` migration + schema
  **Implementation**: Exact code in `research/ecto-schema.md` Migration 7.
  **Locations**: `priv/repo/migrations/*_create_match_frames.exs`, `lib/cuevolution/competitions/match_frame.ex`

- [x] [P1-T3][ecto] `create_cuevo_points_entries` migration + schema
  **Implementation**: Exact code in `research/ecto-schema.md` Migration 8. `participant_id` index is deliberate — this is the `SUM`-aggregation hot path.
  **Locations**: `priv/repo/migrations/*_create_cuevo_points_entries.exs`, `lib/cuevolution/competitions/cuevo_points_entry.ex`

- [x] [P1-T4][direct] Factories: `match_result_factory/0`, `match_frame_factory/0`, `cuevo_points_entry_factory/0`
  **Locations**: `test/support/factory.ex`

## Phase 2: Core Logic [COMPLETE]

- [x] [P2-T1][ecto] `Competitions.record_result/2` + `correct_result/2`
  **Implementation**: `record_result/2` rejects duplicate results (FR-007, backed by T086's unique index) and, when the fixture's category is `"team"`, calls a new `Teams.lock_roster/1` (`Repo.update_all` on both involved teams where `is_nil(roster_locked_at)`, set to `DateTime.utc_now()` — mirrors `Teams.remove_player_from_roster/2`'s plain conditional `update_all` shape, no `Multi` needed since it's not racy). `correct_result/2` captures `prior_value` (snapshot the pre-update struct as jsonb before updating), logs via `Accounts.log_admin_action/4`, and the caller (LiveView) surfaces the downstream-advancement warning per US4 scenario 3 rather than silently correcting.
  **Locations**: `lib/cuevolution/competitions.ex`, `lib/cuevolution/teams.ex` (new `lock_roster/1`)

- [x] [P2-T2][test] `StandingsCalculator` — the tiebreaker cascade (pure module)
  **Implementation**: `Cuevolution.Competitions.StandingsCalculator.rank(entries)` (or similar), zero DB calls, takes plain data structs/maps in and returns ranked output. One test per tiebreaker level, exhaustive: (1) clean win-count ordering, (2) wins-tied resolved by head-to-head, (3) head-to-head-tied resolved by frame differential, (4) frame-differential-tied resolved by total frames, (5) fully-tied case flagged for admin resolution rather than silently guessed (return an explicit `{:tied, [participants]}` marker, don't pick arbitrarily). Write this as **test-first** — tasks.md is explicit this deserves the most exhaustive coverage in the codebase.
  **Locations**: `lib/cuevolution/competitions/standings_calculator.ex`, `test/cuevolution/competitions/standings_calculator_test.exs`

- [x] [P2-T3][ecto] `Competitions.group_standings/1`, `top_advancers/1`
  **Implementation**: Wrap `StandingsCalculator` with real query data (join `match_results` → `fixtures` → `stage_participations` filtered by `group_id`, via `rounds.group_id`). `top_advancers/1` reads the cutoff N from `Competitions.group_config(group.stage_id, group.category).advancer_count` (was hardcoded 8, now configurable, and applies at both Grassroots and Regional) — handles fewer-entrants-than-N and boundary-tie cases (both via the calculator's tie-flagging).
  **Locations**: `lib/cuevolution/competitions.ex`

- [x] [P2-T3b][ecto] `Competitions.round_winners/1` (Circuit/Finals knockout progression)
  **Implementation**: For a completed knockout round (`round.knockout_bracket_id` set), returns the winner `StageParticipation` of every fixture in that round with a recorded result — the pool the admin manually pairs into the next round's fixtures (spec 008 US3b). No group standings/tiebreaker involved — pure per-fixture winner lookup, not the `StandingsCalculator`.
  **Locations**: `lib/cuevolution/competitions.ex`

- [x] [P2-T4][ecto] `record_points/2`, `correct_points/2`, `points_total/1`, team frame-to-points allocation
  **Implementation**: Mirror `record_result/2`/`correct_result/2`'s create/correct shape. `points_total/1` is a live `SUM(points) WHERE participant_id = ^id` — explicit test that a correction immediately reflects with no stale double-counting (SC-006). Team-category frame-to-points allocation (FR-012) supports both per-frame-participant and per-team points modes — test both.
  **Locations**: `lib/cuevolution/competitions.ex`

## Phase 3: LiveViews [COMPLETE]

- [x] [P3-T1][liveview] Rewire `AdminResultsLive` → `ResultEntryLive` (Unplayed tab)
  **Implementation**: Keep the existing `tab`/`switch_tab` chrome. Replace the always-empty fixture list with a `stream/3`-backed unplayed-fixtures list (uncapped across a season). `select_fixture`, `validate_result`, `record_result` events.
  **Locations**: `lib/cuevolution_web/live/admin/admin_results_live.ex`, `admin_results_live.html.heex`

- [x] [P3-T2][liveview] `PointsEntryLive` (Played tab) + `MatchFrameFormComponent`
  **Implementation**: Same module as above (tab-switched, matching existing chrome) with a `played_fixtures` stream. `record_points`/`correct_points` events — correction affordance is a hard requirement (not optional UI). Team-category frame entry uses a real `LiveComponent` (`MatchFrameFormComponent`) since it has internal form state (frame-by-frame winner selection) distinct from the parent's fixture-selection state.
  **Locations**: `lib/cuevolution_web/live/admin/admin_results_live.ex` (extend), `lib/cuevolution_web/live/admin/match_frame_form_component.ex`

## Phase 4: Tests & Verification [COMPLETE]

- [x] [P4-T1][test] `Competitions` results/points context tests
  **Implementation**: `record_result/2` (duplicate rejection, roster-lock side effect on Team category), `correct_result/2` (prior_value capture, admin log), `group_standings/1`/`top_advancers/1` (wrapping real query data through the already-tested calculator, at both Grassroots and Regional, configurable N), `round_winners/1` (Circuit/Finals), `record_points/2`/`correct_points/2`/`points_total/1` (live-SUM-no-stale-double-counting).
  **Locations**: `test/cuevolution/competitions_test.exs` (extend)

- [x] [P4-T2][test] `ResultEntryLive`/`PointsEntryLive` LiveView tests
  **Implementation**: Result entry flow, correction flow with warning banner assertion, points entry + correction flow, team frame entry via the `LiveComponent`.
  **Locations**: `test/cuevolution_web/live/admin_results_live_test.exs`

- [x] [P4-T3][direct] Full verification run
  **Implementation**: `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test`.

## Files to Follow as Patterns

- `lib/cuevolution/teams.ex` — `remove_player_from_roster/2`'s plain conditional `update_all` (template for `lock_roster/1`)
- `lib/cuevolution/accounts.ex` — `log_admin_action/4` (used by `correct_result/2`)
- `lib/cuevolution_web/live/admin/venue_management_live.ex` — inline edit/correction UI pattern

## Patterns to Follow

- `prior_value` jsonb snapshot before every correction, logged via `log_admin_action/4`
- Live `SUM` queries, never cached columns, for anything points-related

## Session Handoff

- **Discovery**: `Team.roster_locked_at` column already exists (added speculatively in an earlier migration), currently unused everywhere — this plan is what finally writes to it.
- **Decisions**: `Competitions` calls into `Teams` (via `lock_roster/1`), not the reverse — keeps the dependency direction consistent with `Competitions` being the "latest" context that depends on the earlier ones.
- **Warnings**: `StandingsCalculator` MUST stay DB-free (pure function) — resist the temptation to have it query `Repo` directly for "convenience"; `group_standings/1`/`regional_top_8/1` are the query-wrapping layer specifically so the tiebreaker logic itself stays trivially testable without DB setup.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Tiebreaker cascade has a subtle bug that silently mis-ranks someone | Exhaustive test-first coverage per tiebreaker level (P2-T2) — this is the single most important test suite in this plan |
| `lock_roster/1` race if two Team-category results for the same team land concurrently | Low real-world likelihood (one result per fixture, `unique_index(:match_results, [:fixture_id])` already prevents duplicate results); `update_all` with `is_nil(roster_locked_at)` guard is naturally idempotent regardless |
| Correction UI lets an admin "silently" fix a result that already fed into a stage advancement | `correct_result/2`'s caller (LiveView) must surface the downstream-advancement warning per US4 scenario 3 — do not ship the correction form without this banner |

## Verification Checklist

- [x] `mix compile --warnings-as-errors` passes
- [x] `mix format --check-formatted` passes
- [x] `mix credo --strict` passes
- [x] `mix test` passes (full suite, no regressions)
- [x] `StandingsCalculator` has a passing test for every tiebreaker level including the fully-tied flagged case
- [x] A Team-category result sets `roster_locked_at` on both teams; an Individual-category result does not
- [x] A points correction immediately changes `points_total/1`'s result with no double-counting
