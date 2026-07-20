# Scratchpad: Competitions Context

**Feature**: `Cuevolution.Competitions` — the largest remaining gap in the Cuevolution app. Owns Stage, Group/GroupMembership, KnockoutBracket, StageCapacityConfig, StageParticipation, Round, Fixture, MatchResult, MatchFrame, CuevoPointsEntry. Satisfies specs 006-009.

**Plan files** (in dependency/build order — this order matters, later plans depend on earlier ones):

1. `plan-1-foundation.md` — Stages, capacity, groups, brackets. No dependencies.
2. `plan-2-draws.md` — Rounds, fixtures, rewires `AdminDrawsLive`. Depends on Plan 1.
3. `plan-3-results-points.md` — Match results, frames, points, tiebreaker cascade, rewires `AdminResultsLive`. Depends on Plan 2.
4. `plan-4-standings.md` — Standings query, PubSub, rewires player `StandingsLive`. Depends on Plan 3.
5. `plan-5-unblock.md` — Closes out the `⚠️ blocked on Competitions` deferrals in `Accounts`/`Teams` (region lock, anonymize, roster freeze). Depends on Plans 2 & 3.

## DECISION: Plan split (2026-07-14)

User chose "5 sequenced plans" over a single giant plan or a schema-vs-UI split, specifically to match tasks.md's own natural build order (5a→5b→5c→5d→5e) and keep each plan independently workable in its own `/phx:work` session.

## Infrastructure notes (from research agents — avoid re-discovering)

- **No `%Scope{}` struct anywhere in this codebase** despite Phoenix 1.8.5 — every context takes domain structs directly as args. Do not introduce Scopes for Competitions.
- **`Phoenix.PubSub` configured but never used** before Plan 4 — Plan 4 is the first real usage, no existing convention to match.
- **Concurrency pattern**: `Ecto.Multi` + atomic conditional `update_all` (see `Teams.create_team/2`), proven via `Task.async_stream` + `async: false` concurrency test files (`test/cuevolution/teams_concurrency_test.exs` is the template).
- **`AdminComponents.@nav_items`/`nav_active?/2`** (in `lib/cuevolution_web/components/admin_components.ex`) is hardcoded to the current 5 admin pages — every new admin route in these plans needs an edit there, not just in `router.ex`.
- **`AdminDrawsLive` already has working, tested participant/venue live-search** (built in a prior session, not part of this plan set) via `AdminComponents.field_search/1` — Plan 2 wires "save" to real persistence, does NOT rebuild the search UI.
- Full research detail (migration code, LiveView breadboard, context patterns, Accounts/Teams integration trace) is in `research/*.md` in this same directory — read the relevant one before starting each plan's implementation rather than re-deriving.

## Stale note (ignore)

An earlier, unrelated `/phx:work` session left a stray note here about an API-error interruption ("Turn ended due to API error... Resume with: /phx:work --continue") — not relevant to this plan set, superseded by this file.

## COMPLETE — 2026-07-18

All 5 plans plus `plan-1b-format-correction.md` (new — corrects the qualification format after mid-stream product feedback) are shipped and verified: `mix format`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test` all clean, 342 tests passing.

**What changed from the original plan set**: Regional no longer has a knockout bracket — Grassroots and Regional are both round-robin (group size + advancer-count admin-configurable via new `stage_group_configs`), and knockout brackets moved to Circuit/Finals, scoped by stage+category rather than by group. See `plan-1b-format-correction.md` for the full corrective migration/schema/context/LiveView work, and the amendment notes at the top of `plan-3-results-points.md` for how `top_advancers/1`/`round_winners/1` were adjusted. Specs 006/007/008 were rewritten in place to match.

Nothing further pending in this plan set.
