# Feature Specification: Match Results & Cuevo Points

**Feature Branch**: `008-match-results-points`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.5) and `requirements/cuevolution-requirements.md` (FR-6.1–FR-6.5, NFR-6.3, NFR-9.1)

**Traceability**: FR-6.1, FR-6.2, FR-6.3, FR-6.4, FR-6.5, NFR-6.3, NFR-9.1

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin enters a match result (Priority: P1)

The admin enters the outcome of a played fixture — winner/loser, or a score where applicable — since players never self-report results.

**Why this priority**: This is the single most foundational action in the entire competition: without recorded results, no group standing, no knockout progression, no Cuevo Points, and no public standings (spec 009) can exist.

**Independent Test**: Can be fully tested by entering a result for a fixture created in spec 007 and confirming the result is stored against that fixture, independent of standings computation or points.

**Acceptance Scenarios**:

1. **Given** a fixture with no recorded result, **When** the admin enters the winner (and score, if applicable), **Then** the result is saved and the fixture is marked as played.
2. **Given** a fixture that already has a result, **When** the admin attempts to enter a second result for it, **Then** the system prevents a duplicate result (an edit/correction path, if needed, is a distinct, explicit action).

---

### User Story 2 - Grassroots results determine group standings and progression (Priority: P1)

Entered results at the Grassroots stage compute each participant's group standing (no knockout at this stage), which the admin uses to decide who progresses to Regional.

**Why this priority**: This is the first real payoff of results entry — turning individual match outcomes into a ranked view the admin can act on for stage advancement (spec 006). It is P1 because Grassroots is the entry stage every participant passes through.

**Independent Test**: Can be tested by entering a full set of group-stage results for a test group and confirming the resulting standings (wins/losses or points, ranked) are computed correctly, independent of the actual "advance to Regional" admin action.

**Acceptance Scenarios**:

1. **Given** all results are entered for a Grassroots group, **When** the standings are viewed, **Then** participants are ranked by their group results (e.g., match wins), providing the basis for the admin's Regional-advancement decisions.

---

### User Story 3 - Regional results identify the top 8 per group for knockout (Priority: P1)

Entered group-stage results at Regional identify the top 8 players/teams per group, and results of the subsequent knockout bracket (spec 006) determine who progresses to Circuit.

**Why this priority**: This is the most structurally complex standings computation in the MVP (group stage feeding a bracket), and is a hard prerequisite for any Circuit-stage participation — without it, Circuit stays permanently empty.

**Independent Test**: Can be tested by entering a full set of Regional group-stage results, confirming the top 8 per group are correctly identified, then entering knockout-bracket results and confirming Circuit-progression candidates are correctly determined.

**Acceptance Scenarios**:

1. **Given** all group-stage results are entered for a Regional group, **When** standings are computed, **Then** exactly the top 8 ranked participants of that group are identified as knockout entrants (or all of them, if the group has fewer than 8 — see spec 006 edge cases).
2. **Given** knockout bracket results are entered, **When** a knockout round completes, **Then** the winning participants are identified as Circuit-progression candidates for the admin to advance.

---

### User Story 4 - Admin corrects a mis-entered result or points value (Priority: P1)

The admin fat-fingers a score or points value during live, in-person data entry (routine at volume, not exceptional) and needs to correct it, with the correction itself traceable to what the value was before and after the fix.

**Why this priority**: Originally deferred as a future iteration, this was reconsidered during system design review: mis-entry during live multi-round data entry is a near-certainty, not an edge case, and the only workaround without this feature (direct database editing) is exactly the kind of unaudited operation the admin-action-log requirement (NFR-9.1) exists to prevent. Promoted to P1 alongside initial result/points entry.

**Independent Test**: Can be tested by entering a result or points value, correcting it, and confirming the corrected value is what's used in all downstream standings/points calculations, with both the original and corrected values visible in the audit trail.

**Acceptance Scenarios**:

1. **Given** a recorded match result, **When** the admin corrects the winner or score, **Then** the result is updated, all dependent standings/knockout computations reflect the corrected value, and the admin action log records both the prior and new value.
2. **Given** a recorded Cuevo Points entry, **When** the admin corrects its value, **Then** the participant's running total recalculates from the corrected value, and the admin action log records both the prior and new value.
3. **Given** a match result or points entry that has already fed into a completed stage advancement (e.g., the participant already moved to the next stage), **When** the admin corrects it, **Then** the system surfaces a warning that downstream advancement may need admin review, rather than silently leaving a now-inconsistent advancement in place.

---

### User Story 5 - Admin enters Cuevo Points from Circuit onward (Priority: P2)

From the Circuit stage forward, the admin manually enters Cuevo Points for each player/team following a match, and the system maintains a running point total used to determine Finals progression.

**Why this priority**: Points only become relevant once Circuit-stage matches begin, which is later in the pipeline than Grassroots/Regional standings — real and required for MVP, but naturally sequenced after the earlier-stage standings mechanics.

**Independent Test**: Can be tested by entering Cuevo Points for a test participant following a Circuit-stage match and confirming their running total updates correctly, independent of Finals-stage advancement itself.

**Acceptance Scenarios**:

1. **Given** a Circuit-stage (or later) match result is entered, **When** the admin enters Cuevo Points for a participant, **Then** the points are recorded against that match and the participant's running total is updated.
2. **Given** a participant has accumulated Cuevo Points across several Circuit-stage matches, **When** their running total is viewed, **Then** it reflects the correct sum of all entered points for that stage.

---

### Edge Cases

- ~~What happens when the admin needs to correct an already-entered result or points value?~~ **Resolved** — see User Story 4 (FR-009/FR-010): correction is a first-class, audited MVP action, not deferred.
- What happens when a match ends in a scenario with no clear winner (e.g., a walkover, retirement, or disqualification)? [NEEDS CLARIFICATION: the result model (FR-001, FR-011) supports winner + optional score, which can represent a walkover as a win with no score, but disqualification/no-result scenarios beyond that are not specified — recommend adding a `result_type` enum (`played`, `walkover`, `disqualification`) if the league needs to distinguish these for records purposes; MVP as specified treats all of them as "participant X won."]
- What happens when Cuevo Points are entered for a participant who has already advanced past Circuit (e.g., a late correction for a Circuit match after they've reached Finals)? **Resolved by User Story 4, Scenario 3**: the correction is applied and the admin is warned to review downstream advancement, rather than the system blocking the correction outright.
- What happens to Cuevo Points accumulation across stages — does the running total reset when moving from Circuit to Finals, or carry over? **Decision (see Assumptions)**: points continue accruing through Finals as a single running total per participant; there is no reset. This is the simplest rule consistent with the source documents' silence on the matter and should be confirmed with the league before the Cuevo Points formula (already flagged as an open item in scope doc §9) is finalized.
- **Team fixture result granularity** [Resolved — see FR-011/FR-012 and the `Match Frame` entity]: a Team-category fixture is modeled as a set of individual frames between paired players from each roster, with the team's win/loss derived from majority of frames won, and Cuevo Points optionally allocated per individual frame participant as well as to the team as a whole. This is a best-effort default based on common pool team-league formats (e.g., best-of-9 individual frames) and **must be confirmed against Cuevolution's actual team match rules before this part of the schema is implemented** — if a Team tie is actually resolved as a single aggregate score rather than discrete frames, FR-011/FR-012 and the `Match Frame` entity should be simplified back to a flat result.
- **Group-standing and top-8 ties** [Resolved — see FR-013]: an explicit, ordered tiebreaker cascade now governs both Grassroots/Regional group ranking and the Regional top-8 cutoff.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow the admin to enter the result (winner/loser, or score if applicable) of a match, and only the admin — players MUST NOT be able to self-report results.
- **FR-002**: The system MUST use entered results to determine group standings at the Grassroots stage (no knockout at this stage), providing the basis for progression decisions to Regional.
- **FR-003**: The system MUST use entered results to determine group standings at the Regional stage and identify the top 8 players/teams per group.
- **FR-004**: The system MUST use entered knockout-bracket results at the Regional stage to determine which participants are candidates for Circuit progression.
- **FR-005**: The system MUST allow the admin to manually enter Cuevo Points for a player/team following a Circuit-stage (or later) match.
- **FR-006**: The system MUST maintain a running total of Cuevo Points per player/team across the Circuit stage (and Finals, per Assumptions below).
- **FR-007**: The system MUST prevent a duplicate result from being recorded against a fixture that already has one.
- **FR-008**: The system MUST log key results/points admin actions for audit purposes (per NFR-9.1, using the shared admin-action-log capability from spec 001).
- **FR-009**: The system MUST allow the admin to correct an already-entered match result, recomputing any dependent group standing/knockout/advancement view from the corrected value, and MUST record both the prior and new value in the admin action log.
- **FR-010**: The system MUST allow the admin to correct an already-entered Cuevo Points value, recalculating the participant's running total from the corrected value, and MUST record both the prior and new value in the admin action log.
- **FR-011**: For Team-category fixtures, the system MUST support recording a set of individual frame results (each frame pairing one player from each roster), in addition to (or instead of, if the league's format is a single aggregate score — see Edge Cases) the overall team result.
- **FR-012**: For Team-category fixtures modeled as individual frames, the system MUST derive the team's overall win/loss from the majority of frames won, and MUST allow Cuevo Points to be entered either per individual frame participant, per team, or both.
- **FR-013**: The system MUST apply a defined, ordered tiebreaker cascade — (1) match wins, (2) head-to-head result between the tied participants, (3) frame/rack differential (frames won minus frames lost), (4) total frames won, (5) admin manual resolution as a last resort — when computing Grassroots/Regional group standings and identifying the Regional top-8 cutoff, so that ranking and advancement are deterministic.

### Key Entities

- **Match Result**: The outcome of a played fixture (spec 007). Attributes: fixture reference, winner reference, score (if applicable), correction history (prior values, if corrected), recorded-by admin reference, timestamp.
- **Match Frame** *(Team-category fixtures only)*: One individual frame within a team tie. Attributes: match result reference, player from each roster, frame winner, frame sequence number.
- **Group Standing** *(computed, not stored as raw input)*: A per-participant, per-group ranking derived from that group's match results, ordered by the FR-013 tiebreaker cascade.
- **Cuevo Points Entry**: A manually entered point value tied to a specific participant and match result (or match frame, for Team-category per-player points). Attributes: participant reference, match result reference, match frame reference (nullable), points value, correction history (prior values, if corrected), recorded-by admin reference, timestamp.
- **Cuevo Points Total** *(computed, not stored as raw input)*: The running sum of a participant's Cuevo Points Entries across Circuit and Finals (no reset between stages — see Assumptions), used to evaluate Finals-progression eligibility.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of played fixtures during testing have exactly one recorded result; zero duplicate results are accepted.
- **SC-002**: Grassroots and Regional group standings computed from a test dataset match a manually-calculated expected ranking in 100% of test cases.
- **SC-003**: The top-8-per-group identification at Regional matches the expected set in 100% of test cases, including the edge case of a group with fewer than 8 entrants.
- **SC-004**: A participant's Cuevo Points running total always equals the sum of their individual point entries, verified after each new entry.
- **SC-005**: Every result and points entry made during testing has a corresponding admin-action-log record.
- **SC-006**: 100% of corrected results/points in testing show both the prior and new value in the admin action log, and all dependent standings/totals reflect only the corrected value (no stale double-counting).
- **SC-007**: Group standings and top-8 cutoffs computed from a test dataset containing intentional ties match the FR-013 tiebreaker cascade's expected output in 100% of test cases.

## Assumptions

- Cuevo Points continue to accrue and matter through the Finals stage (not just "up to" Finals-qualification), since scope doc §4 describes Finals as capacity-capped entry but does not state points stop being tracked once a participant reaches Finals. **Decision**: a single running total per participant carries across Circuit and Finals with no reset — this should still be revisited if the league's Cuevo Points formula (already flagged as an open item in scope doc §9) says otherwise.
- Result and points correction (FR-009/FR-010) is now in MVP scope, reversing the earlier deferral — see User Story 4. It is a value-correction action (old value replaced by new value, both logged), not a full point-in-time revision history of every intermediate edit.
- The FR-013 tiebreaker cascade (match wins → head-to-head → frame differential → total frames won → admin discretion) is a best-effort default based on common pool league conventions, chosen because the source documents are silent on the exact rule and a deterministic rule is required before the `StandingsCalculator` (see plan.md) can be built. **This should be confirmed with whoever owns Cuevolution's competition rules before implementation** — if confirmed different, only the ordered list in FR-013 needs to change, not the surrounding architecture.
- The Team-category individual-frame model (FR-011/FR-012) is similarly a best-effort default pending confirmation of Cuevolution's actual team match format (see Edge Cases) — flagged, not silently assumed correct.
- "Score if applicable" implies some categories/formats may only need a winner/loser (e.g., a knockout match) while others may benefit from a numeric score (e.g., frames won) — the exact score format is an implementation detail deferred to data modeling, not fixed by the source requirements.
