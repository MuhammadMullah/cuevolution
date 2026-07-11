# Implementation Plan: Draws Management

**Branch**: `007-draws-management` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-draws-management/spec.md`

## Summary

Build fixture (draw) entry and editing inside the `Competitions` context (spec 006), supporting single and batch entry per round, locking a fixture from edits once a result exists (spec 008), and dispatching a "fixture assigned"/"fixture updated" notification to both participants via the `Notifications` context (spec 002) on every create/edit.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (batch-friendly fixture entry table — multiple rows editable/submittable together per NFR-6.3), Ecto, `Cuevolution.Notifications.dispatch/3` (spec 002)

**Storage**: PostgreSQL — `rounds` table (stage/group reference, name), `fixtures` table (round_id, participant_a, participant_b, venue_id, scheduled_at timestamptz [stored UTC, rendered in EAT at the view layer], result_id nullable), with a unique index on `(round_id, least(participant_a, participant_b), greatest(participant_a, participant_b))` to enforce FR-007's same-round-duplicate guard regardless of which participant is entered as "a" vs. "b"

**Testing**: ExUnit, `Phoenix.LiveViewTest` for batch fixture entry, notification-dispatch assertions using the mock SMS/email test doubles from spec 002

**Target Platform**: Phoenix LiveView, admin-only entry screens (behind spec 001's RBAC gate)

**Performance Goals**: Batch entry of a full round (8–16 fixtures) submitted and persisted in a single transaction, well under the 2s NFR-1.1 target

**Constraints**: A fixture with a linked result (spec 008) MUST be rejected for edits at the changeset/context level, not just hidden in the UI (defense against direct action calls). Cross-category/cross-stage pairing (FR-006) is validated in the changeset by comparing each participant's `Competitions.StageParticipation` category/stage before insert. Batch entry (FR-009) processes each row as its own `Ecto.Multi` step so one invalid row's changeset error doesn't roll back the others — the batch as a whole returns a per-row success/error report rather than an all-or-nothing transaction.

**Scale/Scope**: One fixture entry/edit flow reused across all four stages; participants can be either Players (Individual Male/Female) or Teams depending on category

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-6.3: minimize manual steps for per-round, per-match volume entry — **gate**: fixture entry UI supports adding multiple fixtures in one submit, not one-at-a-time page reloads.
- NFR-7.2: context boundaries — **gate**: `Fixture`/`Round` schemas live inside `Competitions` (alongside stages/groups from spec 006) since fixtures are fundamentally a competition-structure concept; notification sending is delegated entirely to `Notifications.dispatch/3`.
- NFR-9.1: key admin actions logged — **gate**: fixture create/edit calls the shared admin-action-log function introduced in spec 001.
- NFR-4.4/NFR-5.3/FR-010: no contact-info leakage between participants — **gate**: the notification payload built by `enter_fixtures/2` passes only `opponent.display_name` to `Notifications.dispatch/3`, never `opponent.email`/`opponent.mobile_number` — enforced by a test asserting the dispatched payload's key set.
- System design review §2.3: no same-round duplicate pairing — **gate**: the unique index described under Storage is exercised by a test attempting the same pairing twice in one round (rejected) and once more in a second round (accepted).

## Project Structure

### Documentation (this feature)

```text
specs/007-draws-management/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── competitions.ex                   # Context additions: enter_fixtures/2 (batch), update_fixture/2
└── competitions/
    ├── round.ex                      # Ecto schema: rounds table
    └── fixture.ex                    # Ecto schema: fixtures table

lib/cuevolution_web/
└── live/
    └── admin/
        └── fixture_entry_live.ex     # Batch fixture entry/edit table for a round

priv/repo/migrations/
├── ..._create_rounds.exs
└── ..._create_fixtures.exs

test/cuevolution/competitions/fixtures_test.exs
test/cuevolution_web/live/admin/fixture_entry_live_test.exs
```

**Structure Decision**: Single Phoenix application. `Round`/`Fixture` are added to the existing `Competitions` context from spec 006 (same domain: competition structure), rather than a new context, since fixtures are meaningless without the stage/group they belong to. This feature depends on spec 002 (`Notifications`) and spec 004 (`Venues`, for the venue reference on a fixture).

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
