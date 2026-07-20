# Plan: Competitions Standings (Live Rankings + PubSub)

**Status**: COMPLETE
**Created**: 2026-07-14
**Detail Level**: more
**Input**: project-scope/tasks.md "Context 5: Competitions" T099–T103, specs 009-standings
**Depends on**: Plan 3 (competitions-results-points) — needs `CuevoPointsEntry`, `record_points/2`/`correct_points/2`
**Unblocks**: nothing further in Competitions — this is the last data-facing plan; Plan 5 is independent of this one

## Summary

Add `Competitions.standings_for_category/1` (index-backed ranked query) and the first real `Phoenix.PubSub` usage in this app: a broadcast on points changes that the player-facing `StandingsLive` subscribes to for live re-ranking without a page reload. This is explicitly the one screen tasks.md names `Phoenix.LiveView.stream/3` for.

## Scope

**In Scope:**

- `Competitions.standings_for_category/1`
- `Phoenix.PubSub.broadcast/3` wired into Plan 3's `record_points/2`/`correct_points/2` (this plan edits those functions, doesn't duplicate them)
- Rewire player-facing `StandingsLive`: `stream/3` + PubSub subscribe/`handle_info`
- `EXPLAIN ANALYZE` performance check against seeded volume

**Out of Scope:**

- Any new admin-facing screen (standings ARE points entry, already built in Plan 3 — this plan is the player-facing read side only)

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| PubSub topic | Single `"standings"` topic (not per-category/per-region) | Simplest possible design for MVP scale — StandingsLive re-runs its own filtered query on any points change and re-streams with `reset: true`; splitting topics is premature optimization with no existing PubSub convention to deviate from anyway |
| Topic naming/payload | `Phoenix.PubSub.broadcast(Cuevolution.PubSub, "standings", {:points_updated, participant_id})` | This is the *first* PubSub usage in the app (configured in supervision tree, never used) — no in-house convention to match, so designed fresh per general Phoenix/LiveView community convention |
| Stream reset strategy | Full `stream(socket, :standings, rows, reset: true)` on every update | The whole point is a re-ranked list — an incremental diff would be more complex for no real benefit at this scale |

## Data Model

No new tables. `standings_for_category/1` queries existing `cuevo_points_entries` (from Plan 3), `SUM(points) GROUP BY participant_id`, `ORDER BY points DESC` with stable secondary sort by name for ties — backed by the `cuevo_points_entries.participant_id` index already created in Plan 3.

## Module Structure

- `lib/cuevolution/competitions.ex` — add `standings_for_category/1` (extends Plan 1-3's module)
- `lib/cuevolution_web/live/player/standings_live.ex` (+ `render_standings.html.heex`) — **rewire in place**

## Phase 1: Context [COMPLETE]

- [x] [P1-T1][ecto] `Competitions.standings_for_category/1`
  **Implementation**: Index-backed `ORDER BY points DESC`, stable secondary sort by participant name for ties. Query hits `cuevo_points_entries.participant_id`'s index (from Plan 3 T088).
  **Locations**: `lib/cuevolution/competitions.ex`

- [x] [P1-T2][direct] PubSub broadcast on points changes
  **Implementation**: Edit Plan 3's `record_points/2` and `correct_points/2` (already-existing functions by this point) to call `Phoenix.PubSub.broadcast(Cuevolution.PubSub, "standings", {:points_updated, participant_id})` after a successful `Repo.transaction`/update. This is a small edit to existing functions, not new functions — do the edit here rather than going back to Plan 3's file.
  **Locations**: `lib/cuevolution/competitions.ex`
  **Test**: a subscribed test process receives the broadcast (`Phoenix.PubSub.subscribe/2` in the test, assert_receive) — this is the one concurrency-adjacent test in this plan, but not a `Task.async_stream` race test, just a pub/sub delivery assertion.

## Phase 2: LiveView [COMPLETE]

- [x] [P2-T1][liveview] Rewire player `StandingsLive`
  **Implementation**: `mount/3`: `if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")`, then populate via `stream(socket, :standings, Competitions.standings_for_category(...), reset: true)` — replace the current `standings_rows/1` stub and hardcoded `@regions`/`@stages` module attributes with real `Accounts.list_regions()` and a real stage list. `handle_info({:points_updated, _participant_id}, socket)`: re-run `standings_for_category/1` for the current tab, `stream(..., reset: true)`. Keep existing `switch_tab`/`filter`/`clear_filters` events — they trigger a fresh repopulate (`reset: true`), not a subscription change (still the same `"standings"` topic regardless of tab).
  **Locations**: `lib/cuevolution_web/live/player/standings_live.ex`, `render_standings.html.heex`
  **Files to follow**: `research/liveview-architecture.md` section "7. StandingsLive" for the full event/data-flow detail

## Phase 3: Performance & Tests [COMPLETE]

- [x] [P3-T1][direct] `EXPLAIN ANALYZE` on `group_standings/1`, `regional_top_8/1` (Plan 3), `standings_for_category/1` against realistic seed volumes
  **Implementation**: Seed hundreds of Grassroots participants (per T102's note these degrade first), run `EXPLAIN ANALYZE` on all three query paths, confirm index usage not sequential scans. Add indexes beyond what's already planned if the query plan shows scans.
  **Locations**: N/A (ad-hoc `psql`/`iex -S mix` investigation, document findings in this plan's scratchpad if any new index is needed)

- [x] [P3-T2][test] PubSub + `StandingsLive` live-update tests
  **Implementation**: Broadcast-delivery test (Phase 1). LiveView test: two connected test processes (or one `live/2` session + a direct `Competitions.record_points/2` call from the test) — assert the connected LiveView's rendered HTML updates without navigation after the points change.
  **Locations**: `test/cuevolution/competitions_test.exs` (broadcast test), `test/cuevolution_web/live/standings_live_test.exs`

- [x] [P3-T3][direct] Full verification run + re-confirm Plan 1's concurrency regression guard
  **Implementation**: `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test` — per T103, re-run Plan 1's `advance_to_stage/2` concurrency test as a permanent regression guard (should already be in the suite from Plan 1, just confirm it's still green, no new work needed unless it broke).

## Files to Follow as Patterns

- No existing PubSub usage in the codebase to follow — this is genuinely new; follow standard `Phoenix.PubSub`/LiveView community convention (`connected?/1`-gated subscribe in `mount/3`, `handle_info/2` for incoming broadcasts)
- `lib/cuevolution_web/live/player/standings_live.ex`'s existing tab/filter chrome — keep the UI shape, replace only the data source

## Patterns to Follow

- `stream/3` for uncapped lists (already established elsewhere in this plan set for entered-fixtures/unplayed-fixtures lists)
- `connected?(socket)` guard before any PubSub subscribe (never subscribe during disconnected initial render)

## Session Handoff

- **Discovery**: `Phoenix.PubSub` is configured in `lib/cuevolution/application.ex` but has literally never been used (`grep -rn "PubSub.broadcast\|PubSub.subscribe" lib/` returns nothing prior to this plan) — there is no existing convention to match, this plan sets the first one.
- **Decisions**: Single topic, not per-category — simplicity over premature scoping.
- **Warnings**: `standings_live.ex` currently has `@regions`/`@stages` as hardcoded module attributes (not queried) — these must become real queries in this plan, don't leave them hardcoded while only fixing the ranking data.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Every points correction re-broadcasts to ALL connected StandingsLive sessions regardless of whether their filtered view actually changed | Acceptable at MVP scale (re-running an indexed query on every broadcast is cheap); revisit only if `EXPLAIN ANALYZE` (P3-T1) shows real cost |
| `standings_for_category/1`'s `ORDER BY points DESC` with secondary name sort could still produce ambiguous ties for identical names | Out of scope — genuine full ties are already handled by `StandingsCalculator`'s explicit tie-flagging in Plan 3, not re-solved here |

## Verification Checklist

- [x] `mix compile --warnings-as-errors` passes
- [x] `mix format --check-formatted` passes
- [x] `mix credo --strict` passes
- [x] `mix test` passes (full suite, no regressions)
- [x] A `record_points/2` call from one process is reflected in a *different* connected `StandingsLive` session without that session navigating
- [x] `EXPLAIN ANALYZE` confirms index usage (not sequential scans) on all three standings query paths at seeded volume
