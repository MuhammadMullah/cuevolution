# Implementation Plan: Qualification Pipeline & Stages

**Branch**: `006-qualification-pipeline` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-qualification-pipeline/spec.md`

## Summary

Build a `Competitions` context modeling the four fixed stages, per-participant stage tracking, group/cluster groupings for Grassroots and Regional, a Regional knockout bracket structure, configurable Circuit/Finals capacity limits, and an admin-driven, capacity-checked stage-advancement action. This context is the structural backbone that draws (spec 007) and match results/points (spec 008) both read and write against.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (admin stage/group management screens), Ecto

**Storage**: PostgreSQL — `stages` (seeded lookup: Grassroots/Regional/Circuit/Finals with order), `stage_participations` (player_id or team_id, stage_id, region_id, category, joined_at), `groups` (stage_id, region_id, name), `group_memberships`, `knockout_brackets` (regional group_id), `stage_capacity_configs` (stage_id, category, capacity_limit, current_count — see Constraints below for why `current_count` is tracked here rather than derived at read time)

**Testing**: ExUnit, focused tests on the capacity-check guard (boundary at exactly the configured limit) and on stage-sequencing

**Target Platform**: Phoenix LiveView, admin-only management screens; participant-facing "my current stage" display embedded in player profile/standings views (read-only there)

**Performance Goals**: Capacity checks are a simple count-and-compare query against `stage_participations`; no special performance work needed at MVP scale (hundreds of participants)

**Constraints**: Capacity limits MUST be configuration rows in the database (`stage_capacity_configs`), never `@circuit_men_cap 128`-style module attributes, so admins can change them without a deploy (FR-009/NFR-2.2). **Concurrency-safety (system design review §2.1)**: a naive "count current participants, compare to limit, then insert" check is a TOCTOU race if two advancement actions run concurrently (e.g., the admin has two browser tabs open — a scenario spec 001 already leaves open). `advance_to_stage/2` MUST instead perform the capacity check and the increment atomically: an `UPDATE stage_capacity_configs SET current_count = current_count + 1 WHERE id = $1 AND current_count < capacity_limit RETURNING *` inside the same `Ecto.Multi` transaction as the `stage_participations` insert. If the `UPDATE` affects zero rows, the transaction aborts with a capacity-exceeded error — the same "atomic conditional update" pattern already used correctly for the one-team-per-player guard in spec 005.

**Scale/Scope**: 4 stages, 8 regions, 3 categories (Individual Male, Individual Female, Team); capped stages are Circuit and Finals only

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-2.2: capacity limits stored as configurable values — **gate**: no hardcoded numeric caps anywhere in `Competitions` advancement logic; all reads go through `StageCapacityConfig`.
- System design review §2.1: capacity check must be race-free — **gate**: a concurrency test (two simultaneous `advance_to_stage/2` calls at the last remaining slot) must prove exactly one succeeds and one receives a capacity-exceeded error, never both succeeding.
- NFR-2.1 / NFR-2.3: accommodate future regions/stages/categories without structural redesign — **gate**: `stages`, `regions`, and `categories` are all data rows (seeded), not hardcoded atoms/enums baked into schema constraints that would require a migration to extend.
- NFR-7.3: business rules subject to change stored as data, not code — **gate**: same as above, applied specifically to capacity numbers.
- NFR-7.2: context boundaries — **gate**: `Competitions` owns stage/group/capacity concepts; it references `Accounts.Player` / `Teams.Team` by ID only, never duplicates player/team fields.

## Project Structure

### Documentation (this feature)

```text
specs/006-qualification-pipeline/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── competitions.ex                        # Context: advance_to_stage/2 (capacity-checked),
│                                           #   current_stage/1, assign_to_group/2, capacity_config/2
└── competitions/
    ├── stage.ex                           # Ecto schema: stages table (seeded, ordered)
    ├── stage_participation.ex             # Ecto schema: stage_participations table
    ├── group.ex                           # Ecto schema: groups table
    ├── group_membership.ex                # Ecto schema: group_memberships table
    ├── knockout_bracket.ex                # Ecto schema: knockout_brackets table (Regional only)
    └── stage_capacity_config.ex           # Ecto schema: stage_capacity_configs table

lib/cuevolution_web/
└── live/
    └── admin/
        ├── stage_management_live.ex       # View/advance participants between stages
        ├── group_management_live.ex       # Create groups, assign entrants (Grassroots/Regional)
        └── capacity_config_live.ex        # Edit Circuit/Finals capacity numbers

priv/repo/migrations/
├── ..._create_stages.exs                  # + seed data (Grassroots/Regional/Circuit/Finals, ordered)
├── ..._create_stage_capacity_configs.exs  # + seed default capacities (128/64/20, 64/32/8), current_count starts at 0
├── ..._create_stage_participations.exs
├── ..._create_groups.exs
├── ..._create_group_memberships.exs
└── ..._create_knockout_brackets.exs

test/cuevolution/competitions_test.exs
test/cuevolution/competitions/capacity_config_test.exs
test/cuevolution_web/live/admin/stage_management_live_test.exs
```

**Structure Decision**: Single Phoenix application. `Competitions` is a standalone context per NFR-7.2, holding stage/group/capacity structure only; it exposes `advance_to_stage/2` as the single write path so the capacity-check guard cannot be bypassed by a direct schema update elsewhere in the codebase.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
