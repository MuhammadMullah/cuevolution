# Feature Specification: Public Standings

**Feature Branch**: `009-standings`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.6) and `requirements/cuevolution-requirements.md` (FR-7.1–FR-7.3, NFR-1.2)

**Traceability**: FR-7.1, FR-7.2, FR-7.3, NFR-1.2

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Any registered player can view standings by category (Priority: P1)

A logged-in player views public standings ranked by Cuevo Points for Individual Male, Individual Female, and Team categories, without needing admin privileges.

**Why this priority**: Standings are the primary reason a player keeps coming back to the app once past registration — this is the core "what do I get out of this" payoff feature for the entire competition, and it depends only on points already existing (spec 008).

**Independent Test**: Can be fully tested by logging in as a test player (no admin role) and viewing each of the three category standings, confirming the ranking matches the underlying Cuevo Points data, independent of any other player-facing feature.

**Acceptance Scenarios**:

1. **Given** Cuevo Points have been entered for several Circuit-stage participants, **When** a logged-in player views the Individual Male standings, **Then** participants are listed ranked by points, highest first.
2. **Given** the same underlying data, **When** the player switches to Individual Female or Team standings, **Then** each category shows only its own participants, correctly ranked.
3. **Given** a player with no admin role, **When** they navigate to the standings page, **Then** they can view it without any admin-only restriction or error.

---

### User Story 2 - Standings reflect newly entered points promptly (Priority: P2)

When the admin enters new Cuevo Points, the public standings update to reflect the change within a short, LiveView-appropriate refresh window, without the player needing to manually reload.

**Why this priority**: A real quality-of-life expectation for a live-tournament tool, but standings are still useful even with a basic page-refresh-to-update model — this refines an already-functional feature rather than being required for it to deliver value.

**Independent Test**: Can be tested by having a logged-in player viewing the standings page in one session while an admin enters new points in another, confirming the visible standings update without a manual page reload.

**Acceptance Scenarios**:

1. **Given** a player has the standings page open, **When** the admin enters new Cuevo Points for a participant shown on that page, **Then** the player's view updates to reflect the new ranking without requiring a manual refresh.

---

### Edge Cases

- What happens when two participants are tied on Cuevo Points — what's the tiebreaker/display order? [NEEDS CLARIFICATION: no tiebreaker rule specified]
- What happens for participants who haven't reached Circuit stage yet (no points at all) — are they omitted from standings, or shown at the bottom with zero?
- What happens when a participant's team becomes ineligible (roster drops below 5, spec 005) — do they remain visible in Team standings?
- How far back does "standings" go — is there any pagination/limit for very large participant counts, or is the full ranked list always shown?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST display public standings ranked by Cuevo Points for the Individual Male, Individual Female, and Team categories.
- **FR-002**: Standings MUST be viewable by any registered player without requiring admin privileges.
- **FR-003**: The system MUST update standings whenever new Cuevo Points are entered by the admin.
- **FR-004**: Standings updates MUST be reflected to an already-open standings view within a short refresh window appropriate to a real-time, LiveView-based experience (no manual reload required).

### Key Entities

- **Standing Entry** *(computed, not stored as raw input)*: A per-category, per-participant row combining the participant's identity/region and their current Cuevo Points total (from spec 008), ordered by points descending.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Any logged-in player (no admin role) can reach and view all three category standings without an authorization error, in 100% of test attempts.
- **SC-002**: Standings ranking always matches a manually-recomputed ranking from the underlying Cuevo Points data, in 100% of test cases.
- **SC-003**: A visible standings page reflects a newly entered points value within a few seconds, without the viewer manually reloading the page.

## Assumptions

- Standings are read-only and computed live from Cuevo Points Entries (spec 008); no separate "standings" table is persisted, avoiding any risk of the displayed ranking drifting from the source-of-truth points data.
- Participants with zero Cuevo Points (not yet at Circuit stage) are shown at the bottom of their category ranking rather than omitted, since public visibility of stage progress is part of the platform's value — this should be revisited if a product decision says otherwise.
- Tie-handling defaults to a stable secondary sort (e.g., alphabetical by name) in the absence of a specified tiebreaker rule.
