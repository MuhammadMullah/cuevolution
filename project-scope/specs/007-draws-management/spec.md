# Feature Specification: Draws Management

**Feature Branch**: `007-draws-management`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.4, §7.3) and `requirements/cuevolution-requirements.md` (FR-5.1–FR-5.3, NFR-6.3)

**Traceability**: FR-5.1, FR-5.2, FR-5.3, NFR-6.3

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin enters fixture pairings for a round (Priority: P1)

The admin, having prepared a draw manually (outside the system), enters or uploads the resulting fixture pairings — who plays whom, at which venue, on what date/time — for a given round.

**Why this priority**: This is the mechanism that turns a stage/group's participants (spec 006) into actual scheduled matches; nothing about results entry (spec 008) can happen until fixtures exist.

**Independent Test**: Can be tested by an admin entering a set of fixture pairings for a round and confirming each fixture is stored with correct participants, venue, date, and time, independent of results or notifications being verified.

**Acceptance Scenarios**:

1. **Given** two eligible participants in the same stage/group, **When** the admin enters a fixture pairing them at a venue with a date/time, **Then** the fixture is saved and associated with both participants.
2. **Given** a round with several pairings, **When** the admin enters/uploads all of them, **Then** every pairing is stored as a distinct fixture for that round.

---

### User Story 2 - Participants are notified when a draw is entered (Priority: P1)

As soon as a fixture is entered, both participants receive a notification stating their opponent, venue, date, and time via their chosen channel(s).

**Why this priority**: Per the scope document, this is the entire point of digitizing draws — without notification, entering a draw in the system provides no more value than the admin's original manual/offline process. Tied for P1 with fixture entry since the two together form the minimum useful slice.

**Independent Test**: Can be tested by entering a fixture for two test participants with known notification preferences and confirming each receives a notification with the correct opponent/venue/date/time, using the dispatch capability from spec 002.

**Acceptance Scenarios**:

1. **Given** a fixture is entered pairing Player A and Player B, **When** the save completes, **Then** both Player A and Player B receive a notification containing their opponent's name, the venue, and the date/time.

---

### User Story 3 - Admin edits a draw before the match is played (Priority: P2)

The admin corrects a fixture's venue, date, time, or opponent before the match has been played, and both affected participants receive an updated notification reflecting the change.

**Why this priority**: Necessary for handling real-world scheduling corrections, but the system is still functional for the common case (fixtures entered correctly the first time) without it — a real but secondary requirement.

**Independent Test**: Can be tested by editing an already-entered fixture (before any result exists for it) and confirming both participants receive an update notification with the corrected details.

**Acceptance Scenarios**:

1. **Given** an entered fixture with no result recorded yet, **When** the admin edits its venue, date, or time, **Then** the fixture is updated and both participants receive an update notification with the new details.
2. **Given** a fixture that already has a result recorded (spec 008), **When** the admin attempts to edit it, **Then** the system prevents editing a played fixture. [NEEDS CLARIFICATION: exact behavior after a result exists — block entirely, or allow with an explicit admin override/warning — is not specified]

---

### Edge Cases

- **Cross-category/cross-stage pairing errors** [Resolved — see FR-006]: previously left fully to admin trust; now guarded by a cheap, explicit check (same category, same stage/group) since it catches fat-finger errors before they corrupt standings, at negligible implementation cost. The admin is still trusted on everything the check doesn't cover (e.g., whether the pairing is fair/correct within a valid group).
- **Cross-venue (Grassroots) / cross-region (Regional) pairing errors** [Resolved — see FR-011]: at Grassroots and Regional, a round always belongs to exactly one group (spec 006), and both fixture participants must be members of that group — this transitively enforces "same venue" at Grassroots and "same region" at Regional, with no separate venue/region check needed beyond group membership. Circuit and Finals rounds belong to a knockout bracket instead of a group and have no such restriction — opponents may be drawn from any region.
- What happens when a fixture is entered for a bye (uneven number of participants in a group/bracket round)?
- What happens if a participant's notification send fails (handled by spec 002's retry/logging, but the draws feature must not fail/rollback the fixture save itself if only the notification leg fails)?
- What happens when the same two participants are drawn against each other more than once across different rounds (e.g., group stage vs. knockout)? This is expected and must not be treated as a duplicate-entry error. **Distinct from — and not to be confused with — a duplicate entry of the *same* pairing within the *same* round (double-submit or a repeated CSV row), which FR-007 does treat as an error.**
- What timezone are fixture dates/times entered and displayed in? **Resolved — see FR-008**: stored in UTC, displayed in East Africa Time (UTC+3), Kenya's single timezone.
- What happens if a batch/CSV upload contains some invalid rows alongside valid ones? **Resolved — see FR-009**: valid rows commit, invalid rows are reported individually rather than rejecting the whole batch.
- Does a fixture notification reveal the opponent's private contact details? **Resolved — see FR-010**: no — name only, never email/mobile number.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow the admin to enter or upload fixture pairings (participant vs. opponent, venue, date, time) for a given round.
- **FR-002**: The system MUST trigger a notification to both participants of a fixture upon draw entry, containing opponent, venue, date, and time (via the shared notifications capability, spec 002).
- **FR-003**: The system MUST allow the admin to edit a draw entry prior to the associated match being played, triggering an update notification to both participants.
- **FR-004**: The system MUST prevent editing (or MUST clearly flag as an override) a draw entry that already has a recorded match result.
- **FR-005**: The admin draw-entry/edit interface MUST minimize manual steps given draws are entered in volume, per-round.
- **FR-006**: The system MUST reject a fixture pairing whose two participants are not both in the same category and the same stage/group.
- **FR-007**: The system MUST reject a fixture entry that duplicates an existing fixture's pairing within the same round (same two participants), while permitting the same pairing to recur in a different round.
- **FR-008**: The system MUST store fixture date/time in UTC and display it in East Africa Time (UTC+3) in all admin and player-facing views.
- **FR-009**: A batch/bulk fixture upload MUST commit all individually-valid rows and MUST report each invalid row with its specific error, rather than rejecting the entire batch for one invalid row.
- **FR-010**: A fixture-assignment notification (spec 002) MUST contain the opponent's name only — never the opponent's email address or mobile number.
- **FR-011**: For a round belonging to a Grassroots or Regional group, the system MUST reject a fixture pairing where either participant is not a member of that round's group (transitively enforcing same-venue pairing at Grassroots and same-region pairing at Regional, per spec 006). Rounds belonging to a Circuit or Finals knockout bracket instead of a group have no such restriction — opponents may be drawn from any region.

### Key Entities

- **Fixture (Draw Entry)**: A scheduled matchup for one round. Attributes: round reference, stage/group reference, two participants (players or teams, same category), venue, date, time (stored UTC), result reference (nullable until played), timestamps. Unique per `(round, participant A, participant B)`.
- **Round**: A named grouping of fixtures within a stage, belonging to exactly one of: a Group (Grassroots/Regional, e.g., "Grassroots Group A — Round 2") or a Knockout Bracket (Circuit/Finals, e.g., "Circuit Individual Male — Round of 64").

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of fixtures entered/uploaded during testing produce exactly one notification event per participant (two notifications per fixture).
- **SC-002**: An admin can enter a full round of fixtures (e.g., 8–16 pairings) in a single sitting with minimal repeated navigation (batch-oriented entry, not one full-page form per fixture).
- **SC-003**: 100% of edits to a not-yet-played fixture during testing produce an updated notification to both participants with the corrected details.
- **SC-004**: 100% of cross-category/cross-stage, cross-group (Grassroots/Regional), or same-round-duplicate fixture entry attempts are rejected in testing; 100% of legitimate cross-round rematches are accepted; 100% of Circuit/Finals cross-region pairings are accepted (no restriction at those stages).
- **SC-005**: A batch upload containing a mix of valid and invalid rows in testing commits every valid row and reports every invalid row individually, with zero all-or-nothing rejections.

## Assumptions

- Draw entry supports both a manual per-fixture entry form and a bulk/batch entry or upload path (e.g., entering a full round at once), per NFR-6.3's "minimize manual steps" requirement — exact upload format (CSV, structured form rows) is an implementation detail for later design, not specified in the source requirements.
- Once a fixture has a recorded result, it is treated as locked from further edits for MVP; reopening a played fixture is out of scope unless clarified otherwise.
- The system trusts the admin on everything not mechanically checkable (e.g., whether a pairing is competitively fair within a valid group) but now enforces the cheap, mechanical checks — same category, same stage/group, no same-round duplicate (FR-006/FR-007) — per system design review §3, since these catch real fat-finger errors for negligible implementation cost.
