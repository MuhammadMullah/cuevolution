# Feature Specification: Qualification Pipeline & Stages

**Feature Branch**: `006-qualification-pipeline`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§4, §7.4) and `requirements/cuevolution-requirements.md` (FR-4.1–FR-4.8, NFR-2.1, NFR-2.2, NFR-2.3, NFR-7.3)

**Traceability**: FR-4.1, FR-4.2, FR-4.3, FR-4.4, FR-4.5, FR-4.6, FR-4.7, FR-4.8, NFR-2.1, NFR-2.2, NFR-2.3, NFR-7.3

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every player/team has a tracked current stage (Priority: P1)

The system models the four sequential stages (Grassroots → Regional → Circuit → Finals) and always knows which stage each player/team currently sits in, so admins, standings, and draws can all reason about "who is where."

**Why this priority**: Every other feature in the qualification pipeline — grouping, knockout brackets, capacity-checked advancement, draws, results — depends on there being an authoritative, queryable "current stage" for each participant. Nothing else in this spec (or in draws/results) can be built without it.

**Independent Test**: Can be fully tested by assigning test players/teams to a stage and confirming their current stage is stored and displayed correctly, independent of any grouping, capacity, or advancement logic.

**Acceptance Scenarios**:

1. **Given** a newly registered player or validated team, **When** they enter the qualification pipeline, **Then** their current stage is recorded as Grassroots.
2. **Given** any player/team, **When** their record is viewed (by admin or in public standings), **Then** their current stage (Grassroots/Regional/Circuit/Finals) is clearly displayed.

---

### User Story 2 - Admin groups entrants at Grassroots and Regional stages (Priority: P2)

The admin organizes open-entry participants at the Grassroots stage into groups/clusters (no knockout), and at the Regional stage into groups whose results feed a knockout bracket limited to the top 8 per group.

**Why this priority**: Grouping is what makes the group-stage-only Grassroots format and the group-then-knockout Regional format actually operable; it's needed before any match/result can be meaningfully entered against "the right opponents," but the pipeline's stage-tracking (User Story 1) has to exist first.

**Independent Test**: Can be tested by creating groups within a stage/region and assigning a set of test players/teams to them, confirming group membership is stored and retrievable, independent of actual match results existing yet.

**Acceptance Scenarios**:

1. **Given** open Grassroots-stage entrants in a region, **When** the admin creates groups/clusters and assigns entrants to them, **Then** each entrant's group membership is recorded, with no knockout bracket structure created at this stage.
2. **Given** open Regional-stage entrants in a region, **When** the admin creates groups and assigns entrants, **Then** a knockout bracket structure is available to be populated later from the top 8 of each group (bracket population itself is driven by results — see spec 008).

---

### User Story 3 - Circuit and Finals capacity limits are configurable (Priority: P2)

The admin can adjust the entry caps for Circuit (default 128 men / 64 women / 20 teams) and Finals (default 64 men / 32 women / 8 teams) as configuration values, without requiring a code change, so the league can tune capacity across seasons.

**Why this priority**: Directly required by NFR-2.2 and the scope document's explicit note that these numbers must not be hardcoded; needed before the advancement action (User Story 4) can validate against a cap, but grouping/stage-tracking are still logically prior.

**Independent Test**: Can be tested by changing a capacity value through an admin-facing configuration screen (or config record) and confirming subsequent capacity checks use the new value, independent of any real advancement happening.

**Acceptance Scenarios**:

1. **Given** the default Circuit capacity (128 men / 64 women / 20 teams), **When** the admin changes the Finals capacity for men from 64 to 72, **Then** the new value is used for all subsequent Finals-advancement capacity checks without a deployment.

---

### User Story 4 - Admin advances qualifying players/teams to the next stage (Priority: P1)

The admin moves qualifying players/teams from one stage to the next (e.g., Regional → Circuit), with the system enforcing the configured capacity limit at capped stages (Circuit, Finals).

**Why this priority**: This is the action that actually makes the pipeline function as a pipeline — without it, participants are permanently stuck at Grassroots. It's P1 alongside stage-tracking because the two together are the minimum viable "pipeline."

**Independent Test**: Can be tested by advancing a set of test players/teams from one stage to the next and confirming their current stage updates, and that attempting to exceed a capped stage's configured limit is rejected.

**Acceptance Scenarios**:

1. **Given** a player at Regional stage who qualified via knockout, **When** the admin advances them to Circuit, **Then** their current stage becomes Circuit.
2. **Given** Circuit capacity for men is set to 128 and 128 men are already advanced, **When** the admin attempts to advance a 129th man to Circuit, **Then** the system rejects the action, citing the capacity limit.
3. **Given** Grassroots or Regional stages (open/uncapped), **When** the admin advances any number of qualifying entrants, **Then** no capacity limit is enforced (only Circuit and Finals are capped).

---

### Edge Cases

- What happens when the admin tries to advance a player/team out of sequence (e.g., Grassroots directly to Circuit, skipping Regional)? [NEEDS CLARIFICATION: requirements state stages are sequential but don't explicitly forbid/allow skip-advancement by admin override]
- What happens when a capacity limit is lowered below the number already advanced (e.g., Finals men capacity changed from 64 to 50 after 64 are already in Finals)?
- What happens when a team stops being eligible (roster drops below 5, per spec 005) while it currently occupies a stage/group slot?
- How are groups sized/balanced — is group size itself configurable or admin-discretionary? [NEEDS CLARIFICATION: not specified — assumed admin-discretionary manual grouping for MVP, consistent with manual draw entry]
- What happens at the Regional knockout stage if fewer than 8 entrants exist in a group (small group) — is "top 8" simply "all of them"?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST model four sequential stages: Grassroots, Regional, Circuit, Finals.
- **FR-002**: The system MUST support open (uncapped) participation at the Grassroots and Regional stages.
- **FR-003**: The system MUST support group/cluster groupings at the Grassroots stage, with no knockout bracket structure at this stage.
- **FR-004**: The system MUST support group/cluster groupings at the Regional stage, followed by a knockout bracket limited to the top 8 players/teams per group.
- **FR-005**: The system MUST support configurable capacity limits for Circuit-stage entry, defaulting to 128 men, 64 women, 20 teams.
- **FR-006**: The system MUST support configurable capacity limits for Finals-stage entry, defaulting to 64 men, 32 women, 8 teams.
- **FR-007**: The system MUST allow the admin to advance qualifying players/teams from one stage to the next, enforcing the configured capacity limit at Circuit and Finals.
- **FR-008**: The system MUST track and display each player's/team's current stage at all times.
- **FR-009**: Stage capacity limits MUST be stored as configuration data, not hardcoded constants, and MUST be changeable by the admin without a code deployment.
- **FR-010**: The data model MUST accommodate future stages, categories, or competition formats being added without breaking existing stage/group/advancement records.

### Key Entities

- **Stage**: One of the four fixed pipeline stages (Grassroots, Regional, Circuit, Finals) with a defined sequential order.
- **Stage Participation**: A record of a player's or team's current stage, region, and category (Individual Male / Individual Female / Team), updated as they advance.
- **Group / Cluster**: A named grouping of entrants within a stage (and typically a region), used at Grassroots and Regional stages to organize round-robin-style participation ahead of results entry.
- **Knockout Bracket**: A bracket structure at the Regional stage populated by the top 8 entrants of each group, used to determine Circuit-stage advancement.
- **Stage Capacity Configuration**: A configurable value per stage and category (e.g., Circuit-Men=128, Circuit-Women=64, Circuit-Teams=20, Finals-Men=64, Finals-Women=32, Finals-Teams=8) that advancement actions validate against.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every player/team in the system has exactly one current stage at all times, viewable by the admin and reflected in public standings, with zero "no stage" or "multiple stage" data states in testing.
- **SC-002**: Changing a Circuit or Finals capacity value takes effect for the very next advancement check, with no code change or redeploy.
- **SC-003**: 100% of advancement attempts that would exceed a capped stage's configured limit are rejected in testing; 100% of advancement attempts within an open stage's limits (none) succeed.
- **SC-004**: A new stage, category, or format can be added to the configuration/data model in future phases without a migration that breaks or renumbers existing stage/group/advancement history (validated structurally, not by a runtime test).

## Assumptions

- Group/cluster creation and player/team assignment to groups is a manual admin action for MVP (consistent with manual draw management elsewhere in scope), not an automated seeding/balancing algorithm.
- Advancement is a discrete admin action per player/team (or a bulk action over a selected set), not an automatic trigger fired purely by result entry — the admin has final say on who moves stages, consistent with §5.5 and §6.1's manual-admin-entry model throughout.
- Sequential stage order is enforced as the default path (Grassroots → Regional → Circuit → Finals); an explicit admin override to skip a stage is not assumed to exist unless later clarified.
- Group standings computation and top-8 identification within a Regional group are computed by the Match Results feature (spec 008), which reads this feature's Group/Stage model — this spec owns the structure, spec 008 owns the computation from entered results.
