# Plan: Qualification Format Correction (Groups → venue/region + category, Brackets → Circuit/Finals)

**Status**: COMPLETE
**Created**: 2026-07-18
**Detail Level**: comprehensive
**Input**: Post-Plan-1/2 product feedback (see conversation log) + corrected spec 006/007/008
**Depends on**: Plan 1 (foundation), Plan 2 (draws) — both already shipped/migrated
**Unblocks**: Plan 3 (results-points) — `top_advancers/1`, `StandingsCalculator`, and the Circuit/Finals bracket-round result-entry flow all read this plan's corrected `Group`/`KnockoutBracket`/`StageGroupConfig` model

## Summary

Plan 1 shipped `knockout_brackets` scoped to Regional `groups` (top 8 per group). Product feedback says this is wrong: Grassroots and Regional are both round-robin-only (no knockout), scoped to venue (Grassroots) and region (Regional) respectively, with an admin-configurable group size (default 8) and advancer-count (default 2-3) determining who moves to the next stage. Knockout brackets only exist at Circuit and Finals — one per stage+category, covering every capacity-admitted entrant, opponents from any region. This plan corrects the foundation with a new migration (the original Plan 1 migrations already applied, not edited in place) and the schema/context/LiveView changes that follow from it.

## Scope

**In Scope:**

- Corrective migration: `groups` gains `venue_id` (nullable) + `category`; `knockout_brackets` moves from `group_id` to `stage_id`+`category`; `rounds` gains nullable `knockout_bracket_id` with an exactly-one-of-group-or-bracket CHECK; new `stage_group_configs` table (group_size/advancer_count per stage+category, seeded for Grassroots/Regional × male/female/team)
- `Group`/`KnockoutBracket`/`Round` schema updates; new `StageGroupConfig` schema
- `Competitions.create_group/1` rewritten (no auto-bracket creation; venue required at Grassroots, forbidden at Regional; category required)
- `Competitions.assign_to_group/2` category-match guard
- New: `Competitions.group_config/2`, `update_group_config/2`, `ensure_knockout_bracket/2`, `get_knockout_bracket/2`
- `Competitions.enter_fixtures/2` fixture-pairing restricted to the round's group membership when the round has a `group_id` (Grassroots/Regional); unchanged (any-region) when the round has a `knockout_bracket_id` (Circuit/Finals)
- Factory updates; `GroupManagementLive` category+venue UI; `StageManagementLive` group-config editing UI

**Out of Scope:**

- Match results/points/standings computation itself (Plan 3) — this plan only lays the corrected structural foundation Plan 3 reads from
- Circuit/Finals bracket round-progression helper (`advance_knockout_round/1` or similar) — that's a Plan 3 concern since it depends on `MatchResult`, which doesn't exist yet

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Migration strategy | New corrective migration, not editing Plan 1's applied migrations | User's explicit choice — preserves forward-only migration history |
| Group size / advancer count | Admin-configurable per stage+category, new `stage_group_configs` table | User's explicit choice — mirrors `stage_capacity_configs`' existing pattern rather than hardcoding 8/2 |
| Knockout bracket scope | One per stage+category (Circuit/Finals only), no group relationship | User's explicit choice — the whole stage+category capacity-admitted pool is one bracket, not sub-divided |
| Group category field | Added now (was missing from Plan 1) | `assign_to_group/2` never validated category match — groups could silently mix male/female/team; needed regardless of the venue/knockout correction, and required for `stage_group_configs`' per-category cutoff to mean anything |
| Round↔context linkage | `rounds` gets nullable `knockout_bracket_id` alongside existing nullable `group_id`, CHECK exactly-one-of | Symmetric with `stage_participations`' existing `exactly_one_participant_type` CHECK pattern; avoids denormalizing `category` onto `Round` (derivable via the group/bracket it belongs to) |
| Venue enforcement mechanism | Group membership only (no `venue_id` added to `StageParticipation`) | A Grassroots group is already venue-scoped; restricting fixture pairing to "both participants in this round's group" transitively enforces same-venue pairing without touching `StageParticipation` |

## Data Model

```elixir
# groups — ALTER
add :venue_id, references(:venues, on_delete: :restrict)   # nullable — set for Grassroots, null for Regional
add :category, :string, null: false                         # backfilled 'male' for any pre-existing rows
# drop unique_index [:stage_id, :region_id, :name]
# add unique_index [:stage_id, :region_id, :category, :name] where: "venue_id IS NULL"
# add unique_index [:stage_id, :venue_id, :category, :name] where: "venue_id IS NOT NULL"
# add constraint category_must_be_valid, check: "category IN ('male','female','team')"

# knockout_brackets — recreate columns
# drop group_id, drop its unique_index
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :category, :string, null: false
# unique_index [:stage_id, :category]
# constraint category_must_be_valid

# rounds — ALTER
add :knockout_bracket_id, references(:knockout_brackets, on_delete: :delete_all)   # nullable
# constraint exactly_one_round_context, check: "(group_id IS NOT NULL AND knockout_bracket_id IS NULL) OR (group_id IS NULL AND knockout_bracket_id IS NOT NULL)"

# stage_group_configs — new table
add :id, :binary_id, primary_key: true
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :category, :string, null: false
add :group_size, :integer, null: false, default: 8
add :advancer_count, :integer, null: false, default: 2
# unique_index [:stage_id, :category]
# constraint category_must_be_valid, group_size_must_be_positive, advancer_count_must_be_positive
# seeded: Grassroots × {male,female,team}, Regional × {male,female,team} — group_size=8, advancer_count=2
```

## Module Structure

- `priv/repo/migrations/*_fix_qualification_format.exs` (new)
- `lib/cuevolution/competitions/group.ex`, `knockout_bracket.ex`, `round.ex` (edit)
- `lib/cuevolution/competitions/stage_group_config.ex` (new)
- `lib/cuevolution/competitions.ex` (edit — `create_group/1`, `assign_to_group/2`, `enter_fixtures/2`'s participant resolution, `create_round/1`; new `group_config/2`, `update_group_config/2`, `ensure_knockout_bracket/2`, `get_knockout_bracket/2`)
- `lib/cuevolution_web/live/admin/group_management_live.ex` (+`.heex`), `stage_management_live.ex` (+`.heex`) (edit)
- `test/support/factory.ex` (edit)

## Phase 1: Migration & Schemas

- [x] [P1-T1][ecto] Corrective migration — all four table changes above in one file (they're introduced/altered together and depend on each other: `knockout_brackets`' new `stage_id` FK must exist before `rounds.knockout_bracket_id` references it)
  **Locations**: `priv/repo/migrations/*_fix_qualification_format.exs`
- [x] [P1-T2][ecto] `Group`, `KnockoutBracket`, `Round` schema edits; new `StageGroupConfig` schema
  **Locations**: `lib/cuevolution/competitions/group.ex`, `knockout_bracket.ex`, `round.ex`, `stage_group_config.ex`
- [x] [P1-T3][direct] Factory updates: `group_factory/0` (category + venue for Grassroots variant), `knockout_bracket_factory/0` (stage+category), new `stage_group_config_factory/0`
  **Locations**: `test/support/factory.ex`

## Phase 2: Context Functions

- [x] [P2-T1][ecto] `Competitions.create_group/1` rewrite — no bracket creation; venue required/forbidden by stage name (same lookup pattern as today); category required
- [x] [P2-T2][ecto] `Competitions.assign_to_group/2` — category-match guard, `{:error, :category_mismatch}`
- [x] [P2-T3][ecto] `Competitions.group_config/2`, `update_group_config/2` (mirror `capacity_config/2`/`update_capacity_config/2` exactly)
- [x] [P2-T4][ecto] `Competitions.ensure_knockout_bracket/2`, `get_knockout_bracket/2` (get-or-insert / lookup by stage_id+category)
- [x] [P2-T5][ecto] `Competitions.enter_fixtures/2` → `resolve_participant`/`find_participant` take the preloaded `round`; group-membership restriction when `round.group_id` set; unchanged behavior when `round.knockout_bracket_id` set
- [x] [P2-T6][ecto] `Competitions.create_round/1` accepts `knockout_bracket_id`
- [x] [P2-T7][ecto] `Competitions.list_groups/2` → add `category` param; `list_unassigned_participations/2` → add `category` param

## Phase 3: LiveViews

- [x] [P3-T1][liveview] `GroupManagementLive` — category tab/filter; Grassroots stage shows a venue selector for group creation (in place of the region tab), Regional keeps the region tab
- [x] [P3-T2][liveview] `StageManagementLive`/`CapacityConfigLive` — second bounded table (≤6 rows) for `group_size`/`advancer_count` editing, same inline-edit pattern as the capacity table

## Phase 4: Tests & Verification

- [x] [P4-T1][test] Extend `competitions_test.exs`: corrected `create_group/1` (venue required/forbidden, category required), `assign_to_group/2` category guard, `group_config/2`/`update_group_config/2`, `ensure_knockout_bracket/2`/`get_knockout_bracket/2`, `enter_fixtures/2` group-membership restriction (both accept and reject paths) and unrestricted bracket-round behavior
- [x] [P4-T2][test] `GroupManagementLive`/`StageManagementLive` test extensions for the new UI
- [x] [P4-T3][direct] Full verification: `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test` (zero regressions in Plan 1/2's existing suite)

## Files to Follow as Patterns

- `lib/cuevolution/competitions/stage_capacity_config.ex` + `Competitions.capacity_config/2`/`update_capacity_config/2` — exact template for `StageGroupConfig`/`group_config/2`/`update_group_config/2`
- `lib/cuevolution/competitions/stage_participation.ex`'s `exactly_one_participant_type` CHECK — template for `rounds`' `exactly_one_round_context` CHECK

## Session Handoff

- **Discovery**: `assign_to_group/2` never validated category match between participation and group — a latent gap in Plan 1, not just a consequence of this correction; fixed here since `stage_group_configs`' per-category cutoff only makes sense if groups are category-pure.
- **Decisions**: `Round.category` was deliberately NOT added (derivable via `group.category` or `knockout_bracket.category`) — avoid denormalizing what's already reachable by preload, consistent with the codebase's live-query-over-cached-value convention elsewhere.
- **Warnings**: The `groups` unique-index split into two partial indexes (`venue_id IS NULL` / `venue_id IS NOT NULL`) — don't collapse back into one combined index, it would incorrectly allow/forbid the wrong duplicate-name cases across venues vs. regions.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Backfilling `groups.category` to `'male'` for any pre-existing dev-seeded groups silently mis-categorizes real data | Acceptable — this is pre-launch dev/seed data only, confirmed with the user before choosing the corrective-migration approach |
| Changing `enter_fixtures/2`'s participant resolution to require group membership could break already-passing Plan 2 tests that built fixtures without group setup | Run Plan 2's existing `admin_draws_live_test.exs`/fixture tests after the change; update any test fixtures that relied on the old unrestricted resolution to properly set up group membership first |

## Verification Checklist

- [x] `mix compile --warnings-as-errors` passes
- [x] `mix format --check-formatted` passes
- [x] `mix credo --strict` passes
- [x] `mix test` passes (full suite, no regressions)
- [x] `grep -rn "group_id" lib/cuevolution/competitions/knockout_bracket.ex` returns nothing
- [x] A Grassroots group requires `venue_id`; a Regional group rejects `venue_id`
- [x] `enter_fixtures/2` rejects a group-round pairing where one participant isn't a group member; accepts a knockout-round pairing regardless of region
