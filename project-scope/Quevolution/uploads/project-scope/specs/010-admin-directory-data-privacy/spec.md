# Feature Specification: Admin Directory & Data Privacy

**Feature Branch**: `010-admin-directory-data-privacy`

**Created**: 2026-07-08

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-requirements.md` (FR-9.3, NFR-5.1, NFR-5.2) — identified in `reviews/system-design-review.md` §1.1 as two requirements that were cited in other specs' traceability headers but never actually implemented anywhere.

**Traceability**: FR-9.3, NFR-5.1, NFR-5.2

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin browses and filters all players and teams (Priority: P1)

The admin needs a single place to look up any registered player or team, filtered by region, category, and current qualification stage, instead of only ever seeing individual records in the context of another action (a draw, a result).

**Why this priority**: This is a day-one operational necessity once more than a handful of players exist — the admin cannot run venues, draws, results, or points entry (specs 004, 007, 008) efficiently without being able to find "everyone in Nairobi A currently at Circuit" or "this specific player by username." FR-9.3 requires it explicitly and no other spec provides it.

**Independent Test**: Can be tested by seeding a mix of players/teams across regions, categories, and stages, then confirming the admin directory returns the correct filtered subset for each combination of filters, independent of any draw/result workflow being exercised.

**Acceptance Scenarios**:

1. **Given** players exist across multiple regions and stages, **When** the admin filters the directory by region "Coast" and stage "Circuit", **Then** only players/teams matching both filters are shown.
2. **Given** a player exists with a known username, **When** the admin searches by that username, **Then** the matching player's record is returned.
3. **Given** the admin is viewing the directory, **When** they select a player or team, **Then** they can see that record's full profile (registration details, region, stage, team membership, notification delivery history) in one place.

---

### User Story 2 - Admin anonymizes a player's personal data on request (Priority: P1)

A player (or someone on their behalf) submits a valid data-deletion request. The admin scrubs that player's personally identifiable information from the system while preserving their historical match results, Cuevo Points, and standings entries, since those are shared competition records, not the requester's exclusive personal data.

**Why this priority**: This is a Kenya Data Protection Act, 2019 compliance requirement (NFR-5.1, NFR-5.2), not a nice-to-have — operating without it is a legal exposure the moment the platform holds real players' PII. It's P1 alongside the directory because the admin needs the directory (User Story 1) to find the player in the first place.

**Independent Test**: Can be tested by anonymizing a test player who has existing match results and Cuevo Points, then confirming their PII fields are scrubbed while their historical results/points/standings entries remain intact and still resolve to a (now-anonymized) record rather than a broken reference.

**Acceptance Scenarios**:

1. **Given** a player with recorded matches and Cuevo Points, **When** the admin performs the "anonymize" action on that player, **Then** the player's name, email, mobile number, profile picture, and location/town are irreversibly cleared or replaced with a non-identifying placeholder, while their username may be replaced with a generic identifier (e.g., "Former Player #142").
2. **Given** an anonymized player, **When** their historical match results, Cuevo Points entries, or past standings are viewed, **Then** those records remain intact and display the placeholder identifier rather than an error or a broken reference.
3. **Given** an anonymized player, **When** anyone attempts to log in with their former credentials, **Then** login is rejected (the account is deactivated, not merely renamed).
4. **Given** an anonymized player who was an active team captain or roster member, **When** their team is viewed, **Then** the team reflects the anonymized placeholder in that roster slot rather than losing the historical roster-size record.

---

### Edge Cases

- What happens when the admin attempts to anonymize a player who is a team captain — does the team lose its captain, or does captaincy need reassignment first? [NEEDS CLARIFICATION: no captain-succession mechanic exists yet per spec 005 §"Edge Cases" — this spec's anonymize action should surface a warning and require the admin to resolve captaincy first rather than silently leaving a team captain-less.]
- What happens if a player mid-tournament (with upcoming, unplayed fixtures) is anonymized — should their pending fixtures be withdrawn/forfeited? [NEEDS CLARIFICATION: not specified by source requirements; recommend the admin is warned and must explicitly confirm, since this affects other participants' draws too.]
- What happens to a player's notification preference/history after anonymization — are past notification log entries (spec 002) also scrubbed of contact info, or retained as delivery-status history? [Recommendation: retain delivery status/timestamps for audit purposes, but null out the actual address/number once the player record itself is anonymized, since the notifications context stores its own denormalized snapshot — see Assumptions.]
- What counts as a "valid deletion request" (identity verification of the requester) is an operational/process question outside this system's UI — this spec only covers the mechanical anonymize action once the admin has determined the request is valid.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide the admin with a searchable, filterable view of all registered players, filterable by region, category (Individual Male/Individual Female), and current qualification stage.
- **FR-002**: The system MUST provide the admin with a searchable, filterable view of all registered teams, filterable by region and current qualification stage.
- **FR-003**: The system MUST allow the admin to open a full detail view of any player or team from the directory, showing registration details, current stage, team membership (for players) or roster (for teams), and notification delivery history.
- **FR-004**: The system MUST provide an admin action to anonymize a player's personal data (name, email, mobile number, profile picture, location/town), replacing it with a non-identifying placeholder.
- **FR-005**: The system MUST prevent an anonymized player's former credentials from being used to authenticate.
- **FR-006**: The system MUST preserve all historical match results, Cuevo Points entries, and standings references for an anonymized player rather than deleting or nullifying those rows.
- **FR-007**: The system MUST warn the admin before anonymizing a player who currently holds a team captaincy or has unplayed upcoming fixtures, requiring explicit confirmation.
- **FR-008**: The anonymize action MUST be logged in the admin action log (per spec 001), including which admin performed it and when.

### Key Entities

- **Player** *(extended from spec 003)*: gains an `anonymized_at` timestamp (nullable) and a placeholder-identity state; once set, PII fields are cleared and authentication is disabled.
- **Directory Filter**: Not a persisted entity — a query-time combination of region, category, and stage used to scope the admin's player/team list views.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The admin can locate any specific player or team (by name/username search, or by region+stage filter combination) in under 10 seconds in testing.
- **SC-002**: 100% of anonymized test players retain intact historical match/points/standings records, verified by re-viewing those records post-anonymization.
- **SC-003**: 100% of anonymized test players are rejected on a subsequent login attempt with their former credentials.
- **SC-004**: Every anonymize action performed during testing produces a corresponding admin action log entry.

## Assumptions

- "Anonymize" (not full row deletion) is the correct interpretation of NFR-5.2's "remove or anonymize... where feasible without breaking historical match/points records" — full deletion would break foreign-key history, so anonymization-in-place is the only approach consistent with the rest of the NFR.
- The `Notifications` context (spec 002) stores recipient contact info as a snapshot at send time (for its own delivery-status history) rather than a live join to the player table; anonymizing the player record does not retroactively rewrite past notification log rows, since those already represent historical delivery attempts, not the player's current contact info.
- There is no player-facing self-service "delete my account" flow in MVP — anonymization is an admin-mediated action following an out-of-band valid request, consistent with the single-admin, admin-mediated model used throughout the rest of the system.
- Team roster and captaincy edge cases (see Edge Cases above) are handled as admin-guided manual resolution steps in MVP, not automated reassignment logic — this keeps the feature's scope bounded to what NFR-5.2 actually requires.
