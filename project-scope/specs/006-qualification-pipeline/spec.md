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

The admin organizes open-entry participants at both the Grassroots and Regional stages into round-robin groups — no knockout bracket exists at either stage. Grassroots groups are scoped to a single venue (players/teams only ever play others entered at the same venue); Regional groups are scoped to a single region (same-region opponents only). At both stages, a group's round-robin results determine a top-N ranking (N configurable, see User Story 3b) whose top finishers advance to the next stage.

**Why this priority**: Grouping is what makes the group-stage-only Grassroots and Regional formats actually operable; it's needed before any match/result can be meaningfully entered against "the right opponents," but the pipeline's stage-tracking (User Story 1) has to exist first.

**Independent Test**: Can be tested by creating groups within a stage/venue (Grassroots) or stage/region (Regional) and assigning a set of test players/teams to them, confirming group membership is stored and retrievable, independent of actual match results existing yet.

**Acceptance Scenarios**:

1. **Given** open Grassroots-stage entrants at a venue, **When** the admin creates groups/clusters and assigns entrants to them, **Then** each entrant's group membership is recorded, scoped to that venue, with no knockout bracket structure created at this stage.
2. **Given** open Regional-stage entrants in a region, **When** the admin creates groups and assigns entrants, **Then** each entrant's group membership is recorded, scoped to that region, with no knockout bracket structure created at this stage either — Regional group standings (spec 008) determine the top-N advancers to Circuit directly, the same mechanism as Grassroots→Regional.

---

### User Story 3 - Circuit/Finals capacity and Grassroots/Regional group format are configurable (Priority: P2)

The admin can adjust the entry caps for Circuit (default 128 men / 64 women / 20 teams) and Finals (default 64 men / 32 women / 8 teams), and separately the Grassroots/Regional round-robin group size (default 8) and advancer-count per group (default 2) — all as configuration values, per stage and category, without requiring a code change, so the league can tune both capacity and group format across seasons.

**Why this priority**: Directly required by NFR-2.2 and the scope document's explicit note that these numbers must not be hardcoded; needed before the advancement action (User Story 4) can validate against a cap or determine a group's top-N cutoff, but grouping/stage-tracking are still logically prior.

**Independent Test**: Can be tested by changing a capacity value or a group-size/advancer-count value through an admin-facing configuration screen (or config record) and confirming subsequent checks use the new value, independent of any real advancement happening.

**Acceptance Scenarios**:

1. **Given** the default Circuit capacity (128 men / 64 women / 20 teams), **When** the admin changes the Finals capacity for men from 64 to 72, **Then** the new value is used for all subsequent Finals-advancement capacity checks without a deployment.
2. **Given** the default Grassroots group advancer-count of 2, **When** the admin changes it to 3 for Individual Male groups, **Then** subsequent Grassroots→Regional advancement decisions for Individual Male groups use a top-3 cutoff.

---

### User Story 4 - Admin advances qualifying players/teams to the next stage (Priority: P1)

The admin moves qualifying players/teams from one stage to the next (e.g., Regional → Circuit), with the system enforcing the configured capacity limit at capped stages (Circuit, Finals).

**Why this priority**: This is the action that actually makes the pipeline function as a pipeline — without it, participants are permanently stuck at Grassroots. It's P1 alongside stage-tracking because the two together are the minimum viable "pipeline."

**Independent Test**: Can be tested by advancing a set of test players/teams from one stage to the next and confirming their current stage updates, and that attempting to exceed a capped stage's configured limit is rejected.

**Acceptance Scenarios**:

1. **Given** a player at Regional stage who finished top-N in their round-robin group, **When** the admin advances them to Circuit, **Then** their current stage becomes Circuit.
2. **Given** Circuit capacity for men is set to 128 and 128 men are already advanced, **When** the admin attempts to advance a 129th man to Circuit, **Then** the system rejects the action, citing the capacity limit.
3. **Given** Grassroots or Regional stages (open/uncapped), **When** the admin advances any number of qualifying entrants, **Then** no capacity limit is enforced (only Circuit and Finals are capped).

---

### User Story 5 - Circuit and Finals run as knockout brackets (Priority: P2)

Once a player/team advances into Circuit or Finals, the format switches from round-robin groups to a single-elimination knockout bracket — one bracket per stage and category (Individual Male / Individual Female / Team), covering every capacity-admitted entrant in that stage+category. Entrants pair against opponents from any region (no venue/region restriction, unlike Grassroots/Regional). Bracket rounds are entered manually by the admin, consistent with the manual draw-entry model used everywhere else (spec 007).

**Why this priority**: This is the second qualification format in the pipeline (after round-robin groups) and is a prerequisite for match/result entry (spec 008) at Circuit and Finals — but it's logically after stage-tracking, capacity configuration, and the advancement action (User Stories 1, 3, 4) since it operates on an already-capacity-checked pool of entrants.

**Independent Test**: Can be tested by creating a knockout bracket for a stage+category, entering a round of fixtures against it, and confirming the bracket structure and its rounds are stored and retrievable, independent of actual match results existing yet.

**Acceptance Scenarios**:

1. **Given** entrants have been advanced into Circuit-stage Individual Male, **When** the admin starts the knockout bracket for that stage+category, **Then** a single bracket is created (or reused, if already started) scoped to Circuit + Individual Male, distinct from any other stage/category bracket.
2. **Given** a Circuit-stage knockout bracket, **When** the admin enters a round's fixtures, **Then** opponents may be drawn from any region — no venue/region pairing restriction applies at this stage (unlike Grassroots/Regional).

---

### Edge Cases

- What happens when the admin tries to advance a player/team out of sequence (e.g., Grassroots directly to Circuit, skipping Regional)? [NEEDS CLARIFICATION: requirements state stages are sequential but don't explicitly forbid/allow skip-advancement by admin override]
- What happens when a capacity limit is lowered below the number already advanced (e.g., Finals men capacity changed from 64 to 50 after 64 are already in Finals)?
- What happens when a team stops being eligible (roster drops below 5, per spec 005) while it currently occupies a stage/group slot?
- Group size and advancer-count are admin-configurable per stage+category (default 8 / 2) — resolved, no longer discretionary (see FR-011/FR-012).
- What happens at Grassroots/Regional if fewer than the configured advancer-count of entrants exist in a group (small group) — is the cutoff simply "all of them"?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST model four sequential stages: Grassroots, Regional, Circuit, Finals.
- **FR-002**: The system MUST support open (uncapped) participation at the Grassroots and Regional stages.
- **FR-003**: The system MUST support group/cluster groupings at the Grassroots stage, scoped to a single venue per group, with no knockout bracket structure at this stage.
- **FR-004**: The system MUST support group/cluster groupings at the Regional stage, scoped to a single region per group, with no knockout bracket structure at this stage either — Regional group standings (spec 008) determine the top-N advancers to Circuit using the same round-robin-then-cutoff mechanism as Grassroots.
- **FR-005**: The system MUST support configurable capacity limits for Circuit-stage entry, defaulting to 128 men, 64 women, 20 teams.
- **FR-006**: The system MUST support configurable capacity limits for Finals-stage entry, defaulting to 64 men, 32 women, 8 teams.
- **FR-007**: The system MUST allow the admin to advance qualifying players/teams from one stage to the next, enforcing the configured capacity limit at Circuit and Finals.
- **FR-008**: The system MUST track and display each player's/team's current stage at all times.
- **FR-009**: Stage capacity limits MUST be stored as configuration data, not hardcoded constants, and MUST be changeable by the admin without a code deployment.
- **FR-010**: The data model MUST accommodate future stages, categories, or competition formats being added without breaking existing stage/group/advancement records.
- **FR-011**: The system MUST support a configurable round-robin group size per stage (Grassroots, Regional) and category, defaulting to 8, changeable by the admin without a code deployment.
- **FR-012**: The system MUST support a configurable advancer-count per stage (Grassroots, Regional) and category — the number of top group finishers who qualify for the next stage — defaulting to 2, changeable by the admin without a code deployment.
- **FR-013**: The system MUST support a single knockout bracket per stage (Circuit, Finals) and category, covering every capacity-admitted entrant of that stage+category, with no venue/region restriction on pairing within it.

### Key Entities

- **Stage**: One of the four fixed pipeline stages (Grassroots, Regional, Circuit, Finals) with a defined sequential order.
- **Stage Participation**: A record of a player's or team's current stage, region, and category (Individual Male / Individual Female / Team), updated as they advance.
- **Group / Cluster**: A named grouping of entrants within a stage and category, scoped to a single venue (Grassroots) or region (Regional), used to organize round-robin-style participation ahead of results entry. Never has a knockout bracket.
- **Knockout Bracket**: A single-elimination bracket structure scoped to one stage (Circuit or Finals) and category, populated by every capacity-admitted entrant of that stage+category — distinct from, and unrelated to, Groups. Opponents may be drawn from any region.
- **Stage Capacity Configuration**: A configurable value per stage and category (e.g., Circuit-Men=128, Circuit-Women=64, Circuit-Teams=20, Finals-Men=64, Finals-Women=32, Finals-Teams=8) that advancement actions validate against.
- **Stage Group Configuration**: A configurable value per stage (Grassroots, Regional) and category — round-robin group size (default 8) and advancer-count (default 2) — that group formation and top-N advancement decisions read from.

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
- Group standings computation and top-N identification within a Grassroots or Regional group are computed by the Match Results feature (spec 008), which reads this feature's Group/Stage/Stage Group Configuration model — this spec owns the structure and the configurable N, spec 008 owns the computation from entered results.
- Knockout bracket round entry and progression (Circuit/Finals) are computed by the Draws (spec 007) and Match Results (spec 008) features, which read this feature's Knockout Bracket model — this spec owns the stage+category-scoped bracket structure, spec 007/008 own round/result entry against it.
