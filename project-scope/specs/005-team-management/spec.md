# Feature Specification: Team Registration & Management

**Feature Branch**: `005-team-management`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.2, §7.2) and `requirements/cuevolution-requirements.md` (FR-2.1–FR-2.6)

**Traceability**: FR-2.1, FR-2.2, FR-2.3, FR-2.4, FR-2.5, FR-2.6

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Registered player creates a team and becomes captain (Priority: P1)

A registered player who wants to compete in the Teams category creates a team, automatically becoming its Team Captain, with the team tied to the captain's region.

**Why this priority**: This is the entry point for the entire Teams category — no roster can be built, validated, or entered into any draw without a team existing first.

**Independent Test**: Can be fully tested by having a registered test player create a team and confirming the team exists with that player as captain and the correct region, independent of roster-filling or draws.

**Acceptance Scenarios**:

1. **Given** a registered player who is not already on a team, **When** they create a team, **Then** a team is created, the player is recorded as Team Captain, and the team is associated with the captain's region.
2. **Given** a registered player who is already on a team (as captain or member), **When** they attempt to create another team, **Then** the system blocks the action.

---

### User Story 2 - Captain adds already-registered players to the roster (Priority: P1)

The Team Captain directly adds other already-registered players to the team roster (no invite/accept flow for MVP), and the system prevents adding a player who already belongs to another team.

**Why this priority**: Without the ability to build a roster, a team can never reach the minimum size required to be eligible for draws — this is the core mechanic that makes a team usable.

**Independent Test**: Can be tested by having a captain add several already-registered test players to their roster and confirming the roster updates, while an attempt to add a player already on another team is rejected.

**Acceptance Scenarios**:

1. **Given** a captain viewing their team, **When** they search for and add a registered player who is on no team, **Then** that player is added to the roster and their team reference is updated.
2. **Given** a captain attempts to add a player who is already a member of another team, **When** they submit the add, **Then** the system blocks it with a clear "already on a team" message and the roster is unchanged.
3. **Given** a roster already at 8 players (maximum), **When** the captain attempts to add a 9th, **Then** the system blocks the addition.

---

### User Story 3 - Team eligibility reflects roster size (Priority: P1)

The team's eligibility for draws is automatically determined by whether its roster is within the required 5–8 range, so the admin and captain always know if a team can be entered into a draw.

**Why this priority**: Draws (spec 007) and the qualification pipeline (spec 006) must never include a team that doesn't meet the minimum roster requirement — this is a hard gate on tournament integrity, tied for P1 with roster building itself since the two are meaningless apart.

**Independent Test**: Can be tested by building a roster below 5, confirming the team is flagged ineligible, then adding players until it reaches 5, confirming it becomes eligible — independent of any draw actually being run.

**Acceptance Scenarios**:

1. **Given** a team with fewer than 5 players, **When** its eligibility is checked (e.g., for a draw), **Then** it is marked ineligible/incomplete.
2. **Given** a team with between 5 and 8 players, **When** its eligibility is checked, **Then** it is marked eligible.
3. **Given** an eligible team (5+ players), **When** a player is removed and the roster drops below 5, **Then** the team automatically becomes ineligible again until restored to 5 or more.

---

### Edge Cases

- What happens when a team drops below 5 players after being validated eligible (e.g., a player withdraws)? Per scope doc §9, recommendation is to flag the team ineligible until restored to 5+, rather than blocking the removal outright. [Confirmed handling per scope doc's stated recommendation — see Assumptions.]
- What happens when the captain themselves needs to be removed/replaced — is there a captain-transfer mechanic? [NEEDS CLARIFICATION: no captain succession/transfer flow specified — partially mitigated by FR-008/FR-009's admin override, but a captain-initiated transfer is still not covered]
- What happens when a player search during "add player" returns no matches (e.g., typo)?
- What happens when a captain tries to add a player from a different region than the team's region — is cross-region team membership permitted or blocked? [NEEDS CLARIFICATION: not explicitly addressed; teams are tied to one region but requirements do not state whether all members must individually share that region]
- **Roster changes after the team enters competition** [Resolved — see FR-008/FR-009]: identified in system design review §1.5 as a gap — nothing previously stopped a captain from swapping out the entire roster after the team had already qualified through a stage. A roster freeze now applies once the team's first `Match Result` (spec 008) exists, mirroring the player-level region lock in spec 003. Admin override remains available for legitimate exceptions (injury replacement, etc.), consistent with how spec 008 treats result/points corrections as an audited admin action rather than a rigid, unbendable rule.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a registered player to create a team, becoming its Team Captain.
- **FR-002**: The system MUST allow the Team Captain to add other registered players directly to the team roster (no invite/accept step).
- **FR-003**: The system MUST prevent a player from being added to a team if they are already a member of another team.
- **FR-004**: The system MUST enforce a team roster size of minimum 5 and maximum 8 players.
- **FR-005**: The system MUST mark a team as ineligible for draws whenever its roster falls below 5 players, and automatically clear that flag once the roster returns to 5 or more.
- **FR-006**: The system MUST require a team to be associated with exactly one region.
- **FR-007**: The system MUST prevent a player from creating or joining a second team while already belonging to one (enforces the "at most one team" rule owned by spec 003's Player entity).
- **FR-008**: The system MUST prevent the captain from adding or removing roster members once the team has at least one recorded `Match Result` (spec 008), except via an explicit admin override.
- **FR-009**: The system MUST allow the admin to override the roster freeze (FR-008) to add or remove a player from a competing team's roster, and MUST log the override in the admin action log (spec 001).

### Key Entities

- **Team**: Represents a registered team. Attributes: name, region reference, captain reference (a Player), eligibility status (derived from roster size), roster-locked flag (derived from existence of a `Match Result` involving the team, spec 008), timestamps.
- **Team Membership**: The association between a Team and a Player (roster entry). A Player has at most one active Team Membership at a time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of attempts to add a player already on another team are blocked in testing.
- **SC-002**: 100% of teams with fewer than 5 players are correctly flagged ineligible, and 100% of teams reaching 5–8 players are correctly flagged eligible, across a range of roster-size test scenarios.
- **SC-003**: A captain can build a valid 5–8 player roster in a single sitting without needing any second player's confirmation/acceptance.
- **SC-004**: 100% of captain-initiated roster changes on a team with an existing `Match Result` are blocked in testing unless performed via the admin override path.

## Assumptions

- A team's region is set to the captain's region at creation time (the source documents state teams are tied to a single region but don't specify how it's chosen; captain's region is the simplest, most consistent default).
- When a team's roster drops below 5 after previously being valid, the team is flagged ineligible rather than the removal being blocked outright, per the explicit recommendation in scope doc §9.
- There is no captain succession/transfer flow in MVP; if the original captain's role needs to change, it is handled as an out-of-band admin action rather than a self-service feature.
- Team membership does not require members to share the captain's individual region (not stated as a constraint in the source requirements) — this assumption should be revisited if it proves incorrect.
- The roster freeze (FR-008) is keyed to spec 008's `Match Result` entity for the same reason as spec 003's player region lock — this makes spec 005's freeze check dependent on spec 008's schema existing (or being stubbed) first; sequence accordingly in `tasks.md`. This is a system-design-review-driven addition (§1.5): the source requirements documents don't explicitly ask for a roster freeze, but leaving it out would let a team's roster diverge completely from the one that qualified through earlier stages, which undermines the point of a qualification pipeline. If the league is comfortable with unrestricted squad rotation, FR-008/FR-009 can be dropped without affecting any other requirement in this spec.
