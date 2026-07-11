# Feature Specification: Venue Management

**Feature Branch**: `004-venue-management`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.3) and `requirements/cuevolution-requirements.md` (FR-3.1–FR-3.3)

**Traceability**: FR-3.1, FR-3.2, FR-3.3

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin manages the venue list per region (Priority: P1)

The admin maintains a preloaded list of venues for each of the 8 regions so that players registering in that region have a meaningful set of choices, and so venues can be corrected or retired over time.

**Why this priority**: Player registration (spec 003) depends on a region-specific venue list existing; without this, every player registering would be forced into "Other" for every region, defeating the purpose of the preloaded list.

**Independent Test**: Can be tested by an admin creating, editing, and removing venues for a given region and confirming the changes persist, independent of any player registration happening.

**Acceptance Scenarios**:

1. **Given** an admin is logged in, **When** they create a new venue and assign it to one of the 8 regions, **Then** the venue is saved and immediately available for selection under that region.
2. **Given** an existing venue, **When** the admin edits its name/details, **Then** the update is saved and reflected wherever the venue is displayed.
3. **Given** an existing venue, **When** the admin removes it, **Then** it no longer appears as a selectable option for new registrations (existing players who already selected it keep their historical selection).

---

### User Story 2 - Region-specific venues are offered during registration (Priority: P1)

A visitor registering as a player sees only the venues preloaded for the region they selected, keeping the choice relevant and short.

**Why this priority**: This is the direct payoff of maintaining venues at all — it is exercised every time someone registers, and spec 003 (player registration) has a hard dependency on this list existing and being filterable by region.

**Independent Test**: Can be tested by querying the venue list for a specific region and confirming only that region's venues are returned, independent of the registration UI itself.

**Acceptance Scenarios**:

1. **Given** venues exist for Nairobi A and Coast, **When** a visitor selects "Nairobi A" as their region, **Then** only Nairobi A's venues are offered (Coast's venues are not shown).

---

### User Story 3 - Custom "Other" venue entries are visible to the admin (Priority: P3)

When a player selects "Other" and types a venue name manually, the admin can see that custom entry, so recurring unlisted venues can eventually be added to the preloaded list.

**Why this priority**: A data-quality/visibility nicety that helps the admin curate the venue list over time; it does not block registration or any core competition flow.

**Independent Test**: Can be tested by submitting a registration (or a simulated one) with a custom "Other" venue string and confirming the admin can view it associated with that player.

**Acceptance Scenarios**:

1. **Given** a player registers selecting "Other" and typing a venue name, **When** the admin views that player's record, **Then** the custom venue name they entered is visible.

---

### Edge Cases

- What happens when an admin removes a venue that players have already selected as their preference? [Assumption: historical selections are preserved by reference; the venue is simply no longer offered for new selections — see Assumptions.]
- What happens when an admin tries to create a duplicate venue name within the same region?
- What happens when a region has zero preloaded venues (new region or none entered yet) — visitors registering there would only see "Other."

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow the admin to create, edit, and remove venues, each associated with exactly one of the 8 regions.
- **FR-002**: The system MUST present only the venues belonging to a player's selected region as selectable options during registration.
- **FR-003**: The system MUST store custom ("Other") venue entries submitted by players, associated with that player, and make them visible to the admin.
- **FR-004**: The system MUST prevent removal of a venue from breaking historical player records that reference it (soft-delete/deactivate rather than hard-delete with dangling references).

### Key Entities

- **Venue**: A physical location preloaded per region. Attributes: name, region reference, active/inactive status, timestamps.
- **Custom Venue Entry**: The free-text venue name a player supplies when selecting "Other" at registration; stored on the player's record rather than as a shared Venue.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Venue lists shown during registration always match the selected region with zero cross-region leakage in testing.
- **SC-002**: An admin can add a new venue and have it appear as a selectable registration option within the same session, with no deployment/restart required.
- **SC-003**: 100% of "Other" custom venue submissions during testing are visible on the corresponding player's admin-facing record.

## Assumptions

- Removing a venue is implemented as deactivation (soft delete), not a hard delete, so players who previously selected it retain a valid historical reference.
- Venue "details" beyond name (e.g., address, contact) are not specified as required fields in the source requirements; only name and region are treated as mandatory for MVP, with room to add optional fields later (NFR-2.3).
