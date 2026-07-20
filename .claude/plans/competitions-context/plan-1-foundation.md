# Plan: Competitions Foundation (Stages, Capacity, Groups, Brackets)

**Status**: COMPLETE
**Created**: 2026-07-14
**Detail Level**: comprehensive
**Input**: project-scope/tasks.md "Context 5: Competitions" T064–T076, specs 006-qualification-pipeline
**Depends on**: nothing (first plan in the sequence — everything else in the Competitions context sits on top of this)
**Unblocks**: Plan 2 (competitions-draws), Plan 3 (competitions-results-points), Plan 4 (competitions-standings), Plan 5 (competitions-unblock)

## Summary

Build the base of `Cuevolution.Competitions`: the four fixed pipeline stages (Grassroots/Regional/Circuit/Finals), per-stage/category capacity limits with a concurrency-safe atomic advance, the `StageParticipation` union record (exactly one of player/team) that every later table (Fixture, MatchResult, CuevoPointsEntry) hangs off, and Grassroots/Regional grouping with auto-created knockout brackets. Ships three new admin LiveViews (StageManagementLive, CapacityConfigLive, GroupManagementLive) matching `VenueManagementLive`'s existing chrome.

## Scope

**In Scope:**

- `stages`, `stage_capacity_configs`, `stage_participations`, `groups`, `group_memberships`, `knockout_brackets` tables
- `Competitions.current_stage/1`, `capacity_config/2` (+ admin update), `advance_to_stage/2` (atomic capacity-checked), `assign_to_group/2`
- StageManagementLive, CapacityConfigLive, GroupManagementLive
- Concurrency test for `advance_to_stage/2` (the capacity race at the last remaining slot)

**Out of Scope:**

- Rounds/Fixtures (Plan 2)
- Match results/points/standings (Plans 3–4)
- `Accounts`/`Teams` unblocking (Plan 5) — those need `MatchResult`, which doesn't exist until Plan 3

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Context struct convention | No `%Scope{}` | Codebase has zero `Scope` usage despite Phoenix 1.8.5 — every context takes domain structs directly (`create_team(%Player{} = captain, ...)`). Competitions follows this. |
| Category modeling | Plain `:string` + DB `CHECK IN (...)` | Matches `Player.gender`'s exact pattern, not `Ecto.Enum` — stays consistent with existing convention rather than introducing a new one. |
| Stage/config seeding | `execute/2` raw SQL inside the migration | Guarantees dev/test/CI parity with zero extra seed step; every other Competitions table FKs into `stages`. |
| Capacity race closure | `Ecto.Multi.run/3` + `Repo.update_all` with `inc:` + `where: current_count < capacity_limit` | Direct analogue of `Teams.create_team/2`'s atomic-claim pattern; no raw SQL needed — Ecto's query DSL expresses the conditional increment natively. |
| CHECK constraints | `constraint/3` migration macro | Already used for `players.gender`/`notifications.channel`; fully expresses "exactly one of player_id/team_id" — no raw SQL escape hatch needed. |

## Data Model

```elixir
# stages (seeded: Grassroots order=1, Regional=2, Circuit=3, Finals=4)
add :id, :binary_id, primary_key: true
add :name, :string, null: false
add :order, :integer, null: false
# unique_index [:name], unique_index [:order]

# stage_capacity_configs (seeded: Circuit/Finals only — Grassroots/Regional stay uncapped)
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :category, :string, null: false          # 'male' | 'female' | 'team'
add :capacity_limit, :integer, null: false
add :current_count, :integer, null: false, default: 0
# unique_index [:stage_id, :category]
# constraint category_must_be_valid, capacity_limit_must_be_positive, current_count_must_be_non_negative

# stage_participations — the union type every later table (Fixture, MatchResult, CuevoPointsEntry) references
add :player_id, references(:players, on_delete: :delete_all)   # nullable
add :team_id, references(:teams, on_delete: :delete_all)       # nullable
add :region_id, references(:regions, on_delete: :restrict), null: false
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :category, :string, null: false
add :joined_at, :utc_datetime, null: false
# index [:stage_id, :region_id, :category], index [:player_id], index [:team_id]
# constraint exactly_one_participant_type, check: "(player_id IS NOT NULL AND team_id IS NULL) OR (player_id IS NULL AND team_id IS NOT NULL)"

# groups
add :stage_id, references(:stages, on_delete: :restrict), null: false
add :region_id, references(:regions, on_delete: :restrict), null: false
add :name, :string, null: false
# unique_index [:stage_id, :region_id, :name]

# group_memberships
add :group_id, references(:groups, on_delete: :delete_all), null: false
add :stage_participation_id, references(:stage_participations, on_delete: :delete_all), null: false
# unique_index [:group_id, :stage_participation_id]

# knockout_brackets (Regional-only, one per group)
add :group_id, references(:groups, on_delete: :delete_all), null: false
# unique_index [:group_id]
```

Full migration code (exact, copy-pasteable) is in `.claude/plans/competitions-context/research/ecto-schema.md`, "Migration 1" through "Migration 4".

## Module Structure

- `lib/cuevolution/competitions.ex` — new context module (this plan starts it; Plans 2–4 extend it)
- `lib/cuevolution/competitions/stage.ex`
- `lib/cuevolution/competitions/stage_capacity_config.ex`
- `lib/cuevolution/competitions/stage_participation.ex`
- `lib/cuevolution/competitions/group.ex`
- `lib/cuevolution/competitions/group_membership.ex`
- `lib/cuevolution/competitions/knockout_bracket.ex`
- `lib/cuevolution_web/live/admin/stage_management_live.ex` (+ `.html.heex`)
- `lib/cuevolution_web/live/admin/capacity_config_live.ex` (+ `.html.heex`, or nested tab in StageManagementLive — see Phase 3)
- `lib/cuevolution_web/live/admin/group_management_live.ex` (+ `.html.heex`)

## Phase 1: Migrations & Schemas [PENDING]

- [ ] [P1-T1][ecto] `create_stages` + `create_stage_capacity_configs` migrations and schemas
  **Implementation**: Exact migration/schema code in `research/ecto-schema.md` Migration 1 & 2. Seed 4 stages and Circuit/Finals capacity rows (128/64/20, 64/32/8) via `execute/2` inside the migration. `Stage.changeset/2` and `StageCapacityConfig.changeset/2` exist mainly for admin tooling — stages are effectively read-only in application code.
  **Locations**: `priv/repo/migrations/*_create_stages.exs`, `*_create_stage_capacity_configs.exs`, `lib/cuevolution/competitions/stage.ex`, `lib/cuevolution/competitions/stage_capacity_config.ex`

- [ ] [P1-T2][ecto] `create_stage_participations` migration and schema
  **Implementation**: Exact code in `research/ecto-schema.md` Migration 3. `StageParticipation.changeset/2`'s `validate_exactly_one_participant/1` mirrors the DB CHECK for a friendly changeset error, matching the existing "changeset gives a friendly error, constraint guarantees correctness" pattern from `players.gender`.
  **Locations**: `priv/repo/migrations/*_create_stage_participations.exs`, `lib/cuevolution/competitions/stage_participation.ex`

- [ ] [P1-T3][ecto] `create_groups_and_brackets` migration and schemas (groups, group_memberships, knockout_brackets)
  **Implementation**: One migration file per tasks.md's own T072 bundling. Exact code in `research/ecto-schema.md` Migration 4.
  **Locations**: `priv/repo/migrations/*_create_groups_and_brackets.exs`, `lib/cuevolution/competitions/group.ex`, `group_membership.ex`, `knockout_bracket.ex`

- [ ] [P1-T4][direct] ExMachina factories for all 6 new schemas
  **Implementation**: `stage_factory/0` cycles through the 4 seeded stages (mirror `region_factory`'s `sequence(:region_cycle, & &1) |> rem(length(stages))` pattern — don't build fake stage rows). `stage_capacity_config_factory/0`, `stage_participation_factory/0` (defaults to a player-category participation; team-category built explicitly per test via `insert(:stage_participation, player_id: nil, team_id: insert(:team).id, category: "team")`), `group_factory/0`, `group_membership_factory/0`, `knockout_bracket_factory/0`.
  **Locations**: `test/support/factory.ex`

## Phase 2: Context Functions [PENDING]

- [ ] [P2-T1][ecto] `Competitions.current_stage/1`, `capacity_config/2` + admin update
  **Implementation**: `current_stage(%StageParticipation{} = participation)` returns the participation's stage. `capacity_config(stage_id, category)` returns the matching `StageCapacityConfig` or `nil` (nil = open/uncapped stage, the signal `advance_to_stage/2` checks). Admin update path (`update_capacity_config/2`) is a no-deploy config change per NFR-2.2 — plain changeset update, no Multi needed (not concurrency-critical, admin-only single-writer in practice).
  **Locations**: `lib/cuevolution/competitions.ex`

- [ ] [P2-T2][ecto] `Competitions.advance_to_stage/2` — atomic capacity-checked stage advancement
  **Implementation**: Exact `Ecto.Multi` pattern in `research/ecto-schema.md` "T069's atomic capacity update as Ecto.Multi" — `Multi.run(:capacity_check, ...)` does the atomic `repo.update_all` conditional increment (`where: current_count < capacity_limit`), returns `{:error, :capacity_exceeded}` on zero rows affected; `Multi.update(:participation, ...)` moves the `StageParticipation` to the new stage. No config row (Grassroots/Regional) = never rejects. Lowering a capacity below `current_count` doesn't retroactively break existing participations (nothing re-validates on config update, only new `update_all` conditional checks going forward).
  **Locations**: `lib/cuevolution/competitions.ex`
  **Concurrency test** (required, see Phase 4): two simultaneous `advance_to_stage/2` calls at the last remaining capacity slot → exactly one succeeds. Follow `test/cuevolution/teams_concurrency_test.exs`'s exact `Task.async_stream` + `async: false` shape.

- [ ] [P2-T3][ecto] `Competitions.assign_to_group/2` + auto-bracket creation
  **Implementation**: `assign_to_group(%StageParticipation{} = participation, %Group{} = group)` inserts a `GroupMembership`. Grassroots grouping produces no bracket (FR-003); Regional grouping produces an empty `KnockoutBracket` the first time a group is created for that stage (FR-004) — check inside `create_group/1` (new function, not just `assign_to_group`): if `stage.name == "Regional"`, insert the bracket in the same transaction as the group.
  **Locations**: `lib/cuevolution/competitions.ex`

## Phase 3: LiveViews [PENDING]

- [ ] [P3-T1][liveview] `StageManagementLive` + `CapacityConfigLive`
  **Implementation**: Mirror `venue_management_live.ex`'s exact shape — `select_stage`/`select_region` tab pattern, `advance`/`advance_bulk` events calling `advance_to_stage/2` per selected participation (extract `%{id:}` from assigns before calling the context — never pass the socket in). Recommend nesting `CapacityConfigLive` as a `:panel` tab within the same route via `handle_params` rather than a second full mount (it's one small settings form, ≤6 rows). Route: `/admin/stages`.
  **Locations**: `lib/cuevolution_web/live/admin/stage_management_live.ex` (+ `.html.heex`)
  **Files to follow**: `lib/cuevolution_web/live/admin/venue_management_live.ex` — region-tab select, inline edit form, `assign_form/2` helper

- [ ] [P3-T2][liveview] `GroupManagementLive`
  **Implementation**: Stage tab (Grassroots/Regional) + region tab, `groups` and `unassigned_participants` as plain assigns (bounded per stage/region — flag for `stream/3` promotion later if Grassroots volumes prove costly, per `research/liveview-architecture.md`'s explicit note). `create_group`, `assign_to_group`, `remove_from_group` events.
  **Locations**: `lib/cuevolution_web/live/admin/group_management_live.ex` (+ `.html.heex`)

- [ ] [P3-T3][direct] Wire new routes and nav
  **Implementation**: Add `/admin/stages` and `/admin/groups` to the `:admin_authenticated` `live_session` in `router.ex`. Add both to `AdminComponents.@nav_items` and `nav_active?/2` clauses (currently hardcoded to `:dashboard, :draws, :results, :directory, :venues` — this file must be edited, not just the router).
  **Locations**: `lib/cuevolution_web/router.ex`, `lib/cuevolution_web/components/admin_components.ex`

## Phase 4: Tests & Verification [PENDING]

- [ ] [P4-T1][test] `Competitions` context tests
  **Implementation**: `current_stage/1`, `capacity_config/2` + update, `advance_to_stage/2` (open-stage-never-rejects case, capacity-exceeded case, boundary-exactly-at-limit case), `assign_to_group/2` + auto-bracket creation (Grassroots-no-bracket vs Regional-bracket assertions). Separate `test/cuevolution/competitions_concurrency_test.exs` for the `advance_to_stage/2` race, `async: false`, following `teams_concurrency_test.exs`'s exact structure.
  **Locations**: `test/cuevolution/competitions_test.exs`, `test/cuevolution/competitions_concurrency_test.exs`

- [ ] [P4-T2][test] LiveView tests
  **Implementation**: `StageManagementLive`/`CapacityConfigLive`/`GroupManagementLive` — mount + auth redirect (mirror `admin_draws_live_test.exs`'s `log_in_admin/1` pattern), stage advance flow, capacity edit flow, group creation + assignment flow.
  **Locations**: `test/cuevolution_web/live/admin/stage_management_live_test.exs`, `group_management_live_test.exs`

- [ ] [P4-T3][direct] Full verification run
  **Implementation**: `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test` (whole suite, confirm zero regressions).

## Files to Follow as Patterns

- `lib/cuevolution/teams.ex` — `Ecto.Multi` + atomic-claim concurrency pattern (`create_team/2`, `add_player_to_roster/2`)
- `test/cuevolution/teams_concurrency_test.exs` — concurrency test structure
- `lib/cuevolution_web/live/admin/venue_management_live.ex` (+ `.html.heex`) — full CRUD admin LiveView chrome
- `lib/cuevolution/accounts.ex` — context module shape, `list_x_filtered/1` pattern
- `test/support/factory.ex` — factory conventions (`region_factory`'s cycling pattern is the template for `stage_factory`)

## Patterns to Follow

- No `%Scope{}` — pass domain structs directly
- Error tuples: `{:ok, x}` / `{:error, %Ecto.Changeset{}}` / `{:error, :atom_reason}`
- `@moduledoc`/`@doc` cite spec + FR numbers (spec 006, FR-00X)
- Private helpers as `defp` immediately after their caller, same module

## Session Handoff

- **Discovery**: No `Phoenix.PubSub` usage exists anywhere in the app yet (configured in `application.ex` but never broadcast/subscribed) — not needed in this plan, but Plan 4 will be the first real usage.
- **Decisions**: `StageParticipation` is the union type every later Fixture/MatchResult/CuevoPointsEntry references — this avoids re-deriving player-or-team polymorphism at every later layer (Iron Law #3).
- **Warnings**: Postgres `order` is a reserved word — the seed SQL in Migration 1 double-quotes it; the Ecto DSL column (`add :order, :integer`) needs no escaping since Postgrex quotes identifiers automatically.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `advance_to_stage/2` race not actually closed if a second `Multi.update` step also touches `current_count` | The atomic `update_all` with `where: current_count < capacity_limit` is the *only* writer of `current_count` — `Multi.update(:participation, ...)` never touches it, so there's no double-write path to worry about |
| Grassroots/Regional "uncapped" represented by absent config row is easy to misread as a bug | Document clearly in `capacity_config/2`'s `@doc` and in the migration comment (already done in `research/ecto-schema.md`) — `nil` return is the intentional "open" signal |
| New admin nav entries break existing `nav_active?/2` clauses for other pages | Add new clauses, don't modify existing ones; run full `PlayerDirectoryLiveTest`/`VenueManagementLiveTest` suite after the edit |

## Self-Check (Deep Plan)

1. **Hardest decision**: Whether `StageParticipation` should be the FK target for `Fixture`/`MatchResult` (vs. a nullable `player_id`/`team_id` pair directly on those tables). Chose `StageParticipation` — it already solves the exactly-one-of-player/team problem once; re-solving it on every downstream table would be the Rails-polymorphic anti-pattern Iron Law #3 warns against, at the cost of one extra join everywhere.
2. **Alternatives rejected**: `Ecto.Enum` for `category` — rejected in favor of plain `:string` + CHECK to match the existing `Player.gender` convention exactly rather than introduce a second enum-modeling style in the same codebase.
3. **Least confident about** ⚠️: Whether `gen_random_uuid()` is available in the target Postgres without the `pgcrypto` extension — flagged in `research/ecto-schema.md`; confirm during T1 implementation (`SELECT gen_random_uuid()` in `psql`) before relying on it in the seed SQL, falling back to `Ecto.UUID.generate()` via `Repo.insert_all` in a seeds script if not.

## Verification Checklist

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix format --check-formatted` passes
- [ ] `mix credo --strict` passes
- [ ] `mix test` passes (full suite, no regressions)
- [ ] `advance_to_stage/2` concurrency test passes reliably (run 3x to rule out flakiness)
- [ ] New admin nav entries render correctly and don't break existing tab highlighting
