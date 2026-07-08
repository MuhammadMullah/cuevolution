# Implementation Plan: Match Results & Cuevo Points

**Branch**: `008-match-results-points` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-match-results-points/spec.md`

## Summary

Add result entry against fixtures (spec 007), compute Grassroots/Regional group standings and Regional top-8 identification from entered results, and add manual Cuevo Points entry with a running total from Circuit onward. Standings computation reads the `Group`/`KnockoutBracket` structure from spec 006; the running points total feeds the public standings feature (spec 009).

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (result/points entry forms, standings preview table), Ecto

**Storage**: PostgreSQL — `match_results` table (fixture_id unique, winner reference, score jsonb/columns, prior_value jsonb snapshot for corrections, recorded_by admin_id), `match_frames` table (match_result_id, player references, frame winner, sequence — Team-category fixtures only), `cuevo_points_entries` table (participant reference, match_result_id, match_frame_id nullable, points, prior_value jsonb snapshot for corrections, recorded_by admin_id); group standings and points totals are computed via query, not stored as duplicated mutable state

**Testing**: ExUnit with fixture-based scenarios covering: a full group's results → expected standings; a Regional group with <8 entrants → top-8 logic; a tied-at-boundary group → FR-013 tiebreaker cascade applied correctly; a sequence of points entries → running total; a result/points correction → old value logged, dependent totals recompute cleanly

**Target Platform**: Phoenix LiveView, admin-only entry screens (behind spec 001's RBAC gate)

**Performance Goals**: Standings queries computed on-demand for the group sizes involved in MVP (well under NFR-1.1's 2s target); no need for pre-materialized standings tables at this scale

**Constraints**: `match_results.fixture_id` has a unique constraint to enforce FR-007's "no duplicate result" rule at the database level; Cuevo Points totals must always be a live sum, never a separately-stored counter that can drift (FR-006/SC-004); corrections (FR-009/FR-010) are implemented as an `UPDATE` that captures the pre-update row into a `prior_value` jsonb column, not a delete+reinsert, so the admin action log can report old vs. new in one place

**Scale/Scope**: Applies across all 4 stages for result entry; Cuevo Points entry applies from Circuit stage onward only

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- FR-007: no duplicate results — **gate**: unique index on `match_results.fixture_id`, not just changeset validation.
- FR-006/SC-004: points totals always equal sum of entries — **gate**: total is a query (`SUM(points)` grouped by participant), never a cached column without a matching invalidation test.
- FR-009/FR-010/SC-006: corrections logged with old + new value — **gate**: `correct_result/2` and `correct_points/2` both capture the pre-update struct into `prior_value` before writing, in the same transaction as the admin-action-log call.
- FR-013/SC-007: deterministic tiebreaker cascade — **gate**: `StandingsCalculator` implements the five-step cascade as an explicit, ordered comparator with a dedicated test per tiebreaker level (wins-only tie, head-to-head tie, frame-differential tie, total-frames tie, full-tie-requiring-admin-flag).
- NFR-9.1: admin actions logged — **gate**: result entry, points entry, and both correction actions call the spec 001 admin-action-log function.
- NFR-7.2: context boundaries — **gate**: `MatchResult`/`MatchFrame`/`CuevoPointsEntry` live in `Competitions` (same context as stages/groups/fixtures) since standings computation is fundamentally a competition-structure concern, not a separate domain.

## Project Structure

### Documentation (this feature)

```text
specs/008-match-results-points/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── competitions.ex                       # Context additions: record_result/2, correct_result/2,
│                                          #   group_standings/1, regional_top_8/1, record_points/2,
│                                          #   correct_points/2, points_total/1
└── competitions/
    ├── match_result.ex                   # Ecto schema: match_results table (+ prior_value snapshot)
    ├── match_frame.ex                    # Ecto schema: match_frames table (Team-category only)
    ├── cuevo_points_entry.ex             # Ecto schema: cuevo_points_entries table (+ prior_value)
    └── standings_calculator.ex           # Pure module: FR-013 tiebreaker cascade + top-8 ranking logic

lib/cuevolution_web/
└── live/
    └── admin/
        ├── result_entry_live.ex          # Result entry + correction against a fixture
        └── points_entry_live.ex          # Cuevo Points entry + correction against a Circuit+ match result

priv/repo/migrations/
├── ..._create_match_results.exs
├── ..._create_match_frames.exs
└── ..._create_cuevo_points_entries.exs

test/cuevolution/competitions/standings_calculator_test.exs
test/cuevolution/competitions/results_and_points_test.exs
test/cuevolution/competitions/corrections_test.exs
test/cuevolution_web/live/admin/result_entry_live_test.exs
```

**Structure Decision**: Single Phoenix application. Standings/ranking logic is isolated in a pure `StandingsCalculator` module (no DB access) so group-standing and top-8 rules can be unit tested exhaustively with fixture data, separate from the Ecto-querying context functions that feed it.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
