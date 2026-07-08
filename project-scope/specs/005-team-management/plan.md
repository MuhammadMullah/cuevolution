# Implementation Plan: Team Registration & Management

**Branch**: `005-team-management` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-team-management/spec.md`

## Summary

Build a `Teams` context supporting team creation (captain assignment, region inheritance), direct roster additions with a one-team-per-player guard, and derived eligibility (5–8 player range) recalculated on every roster change. This feature reads/writes the `team_id` reference owned by `Accounts.Player` (spec 003) and is a hard prerequisite for the Teams category throughout the qualification pipeline (spec 006) and draws (spec 007).

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (captain's team management screen: roster list, add-player search/typeahead), Ecto, `Ecto.Multi` for the add-player transaction (guard check + membership insert + player update must be atomic)

**Storage**: PostgreSQL — `teams` table, `team_memberships` table (or a `team_id` FK directly on `players` if a single active membership is sufficient — see Structure Decision)

**Testing**: ExUnit, `Phoenix.LiveViewTest` for the captain's roster-management LiveView, concurrency test for the one-team guard (two simultaneous add-attempts for the same player)

**Target Platform**: Phoenix LiveView, player-facing (behind spec 003's player auth)

**Performance Goals**: Roster add/remove and eligibility recalculation complete within a single request (no async needed at this scale — teams cap at 8 players)

**Constraints**: The "already on another team" check and the roster-add must be atomic (`Ecto.Multi` + a unique constraint on `players.team_id` or equivalent) to avoid a race where two captains add the same player concurrently

**Scale/Scope**: Up to 8 regions × an open-ended number of teams per region, each capped at 8 players

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- FR-2.3 / NFR-4.5: one-team invariant enforced at the database level (unique/exclusion constraint), not application-logic-only — **gate**: a concurrent add-attempt test must prove the constraint, not just the changeset validation, blocks the second add.
- NFR-7.2: context boundaries — **gate**: `Teams` never modifies `players` table columns other than the `team_id` reference; captain/roster concepts stay inside `Teams`.
- NFR-2.3: data model accommodates future formats without breaking records — **gate**: eligibility is computed (roster count query), not a manually-toggled boolean that can drift from actual roster state.

## Project Structure

### Documentation (this feature)

```text
specs/005-team-management/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── teams.ex                       # Context: create_team/2, add_player_to_roster/2,
│                                   #   remove_player_from_roster/2, eligible?/1
└── teams/
    └── team.ex                    # Ecto schema: teams table (name, region_id, captain_id)

lib/cuevolution_web/
└── live/
    └── team/
        ├── team_dashboard_live.ex      # Captain's roster view + eligibility status
        └── team_creation_live.ex       # Create-team form (registered, teamless players only)

priv/repo/migrations/
├── ..._create_teams.exs
└── ..._add_team_id_to_players.exs      # team_id FK on players (nullable, one active team per player)

test/cuevolution/teams_test.exs
test/cuevolution_web/live/team/team_dashboard_live_test.exs
```

**Structure Decision**: Single Phoenix application. Team membership is modeled as a single nullable `team_id` foreign key directly on `players` (rather than a separate join table) since a player can belong to at most one team at a time — this makes the "already on a team" invariant enforceable as a straightforward not-null check plus application guard, with no need for a many-to-many join table given the 1:1 (player:active-team) cardinality.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
