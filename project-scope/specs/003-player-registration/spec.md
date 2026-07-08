# Feature Specification: Player Registration & Profile

**Feature Branch**: `003-player-registration`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.1, §7.1) and `requirements/cuevolution-requirements.md` (FR-1.1–FR-1.10, NFR-1.1, NFR-4.1, NFR-5.1–NFR-5.3, NFR-6.1, NFR-6.2, NFR-8.1)

**Traceability**: FR-1.1, FR-1.2, FR-1.3, FR-1.4, FR-1.5, FR-1.6, FR-1.7, FR-1.8, FR-1.9, FR-1.10, NFR-1.1, NFR-4.1, NFR-5.1, NFR-5.2, NFR-5.3, NFR-6.1, NFR-6.2, NFR-8.1

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visitor registers as a player (Priority: P1)

A visitor to Cuevolution fills out a registration form providing their personal details, chooses a unique username, selects their region and preferred venue, and sets a notification preference, resulting in a created player account and a confirmation notification.

**Why this priority**: This is the entry point for every participant in the entire league — no team, draw, result, or standing can exist without registered players first. It is the single most foundational user journey in the MVP.

**Independent Test**: Can be fully tested by submitting a complete, valid registration form as an anonymous visitor and confirming a player account is created with all submitted fields persisted, independent of teams, draws, or any later-stage feature existing.

**Acceptance Scenarios**:

1. **Given** a visitor is on the registration form, **When** they submit full name, date of birth (age 18+), gender, email, mobile number, profile picture, location/town, a unique username, one of the 8 regions, a venue selection, and a notification preference, **Then** a player account is created and a registration-confirmation notification is sent via the chosen channel(s).
2. **Given** a visitor enters a date of birth resulting in an age under 18, **When** they submit the form, **Then** registration is rejected with a clear error and no account is created.
3. **Given** a visitor enters a username already taken by another player, **When** they submit the form, **Then** registration is rejected with a clear "username taken" error and no account is created.
4. **Given** a visitor selects a region, **When** they view the venue selection step, **Then** only venues preloaded for that region are offered, plus an "Other" option to manually specify a venue name.
5. **Given** a visitor completes registration, **When** the account is created, **Then** exactly one of Email, SMS, or Both is stored as their notification preference (no default silently applied without the user choosing).

---

### User Story 2 - Player updates notification preference (Priority: P2)

A registered player decides to change how they receive notifications (e.g., switching from Email only to Both) after their account already exists.

**Why this priority**: A real but secondary convenience — registration and the confirmation/fixture notification pipeline (spec 002) work correctly on day one using whatever preference was set at signup; changing it later is valuable but not blocking for MVP launch.

**Independent Test**: Can be tested by logging in as an existing player, changing the stored preference, and confirming subsequent notification events (simulated) honor the new preference.

**Acceptance Scenarios**:

1. **Given** a logged-in player, **When** they change their notification preference and save, **Then** the new preference is persisted and used for all future notification events.

---

### User Story 3 - Player's region locks after their first recorded match (Priority: P2)

A player who registered under one region but has not yet played a match can still correct/change their region; once a match has been recorded for them, the region becomes locked to preserve the integrity of regional standings and pipelines.

**Why this priority**: Protects data integrity of the regional qualification pipeline once competition begins, but has no effect until match results exist (spec 008), so it can land slightly after the core registration flow without blocking it.

**Independent Test**: Can be tested by changing a test player's region before any match record exists (should succeed), then simulating a match record for that player and attempting the change again (should be blocked).

**Acceptance Scenarios**:

1. **Given** a player has no recorded `Match Result` (spec 008), **When** they change their region, **Then** the change is saved successfully — this includes players who already have a scheduled, unplayed fixture (spec 007), since a fixture alone is not yet a "match played."
2. **Given** a player has at least one recorded `Match Result`, **When** they attempt to change their region, **Then** the system blocks the change and explains that region is locked after a player's first played match.

> **Resolved ambiguity** (flagged in system design review §1.4): "first recorded match" means the existence of a `Match Result` row (spec 008) referencing the player — i.e., a match that has actually been played and had its outcome entered — not the existence of a scheduled `Fixture`/draw entry (spec 007). A player with an upcoming, unplayed fixture can still change region up until that match's result is entered.

---

### Edge Cases

- What happens when a visitor is exactly 18 years old on the registration date (boundary condition)? Must be accepted (18+ is inclusive per FR-1.2).
- What happens when a visitor selects "Other" for venue but leaves the manual entry blank?
- What happens when profile picture upload exceeds size/type limits? [NEEDS CLARIFICATION: file size/type constraints are explicitly deferred in scope doc §9 — needs a concrete limit before implementation]
- What happens when a username differs only by case (e.g., "JohnD" vs "johnd") — is uniqueness case-sensitive or case-insensitive? [NEEDS CLARIFICATION: not specified]
- What happens if a player attempts to register twice with the same email but a different username?
- What happens when a player who is already on a team (FR-1.10) is part of the data being edited — region/profile edits must not silently detach them from their team.
- What format is a valid mobile number, given SMS delivery (spec 002) requires a dispatchable number? **Resolved — see FR-013**: normalized to E.164 with a Kenyan (`+254`) default country code assumed for numbers entered without one.
- How does the required `gender` field map to the two individual competition categories (Individual Male, Individual Female)? **Resolved — see FR-014 and Assumptions**: for MVP, `gender` is collected as a controlled choice of exactly "Male" or "Female" and is used directly as the player's competition category — there is no separate, independent "category" field. This is a narrower default than a fully open-ended gender field would allow, chosen specifically because the competition model (scope doc §3) only has two individual categories and an unmapped third value would leave a player without a category. **This default should be confirmed with the league** — if a more inclusive gender field is required with a separate category-assignment step, FR-014 and the `Player` entity need to change before implementation, not after.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a visitor to register as a player by providing: full name, date of birth (or age), gender, email, mobile number, profile picture, location/town, and region.
- **FR-002**: The system MUST reject registration if the calculated age is under 18.
- **FR-003**: The system MUST require a username at registration and enforce uniqueness across all players.
- **FR-004**: The system MUST require the player to select exactly one region from the 8 defined regions at registration.
- **FR-005**: The system MUST allow the player to select a preferred venue from a preloaded list specific to their region, or select "Other" and manually specify a venue name.
- **FR-006**: The system MUST require the player to select a notification preference of Email, SMS, or Both at registration.
- **FR-007**: The system MUST allow the player to update their notification preference after registration.
- **FR-008**: The system MUST allow a player to change their selected region only if they have no recorded match; once a match record exists for the player, the region MUST be locked from further change.
- **FR-009**: The system MUST send a registration-confirmation notification via the player's selected channel(s) upon successful registration (dispatched through the shared notifications capability — see spec 002).
- **FR-010**: The system MUST enforce that a player can belong to at most one team at any time (the underlying association is owned here; enforcement during team-add actions is specified in spec 005).
- **FR-011**: The system MUST authenticate players via credentials distinct from the admin account (see spec 001), with passwords stored using an industry-standard salted hash.
- **FR-012**: The registration form MUST be completable on a standard mobile browser and communicate validation errors (age restriction, duplicate username, etc.) immediately/inline.
- **FR-013**: The system MUST normalize a submitted mobile number to E.164 format (assuming a Kenyan `+254` country code when none is given) before storing it, and MUST reject a number that cannot be normalized to a valid E.164 value.
- **FR-014**: The system MUST collect `gender` as a controlled choice of "Male" or "Female" and MUST use that value directly as the player's competition category (Individual Male / Individual Female) — see Assumptions for why this is narrower than an open-ended field.

### Key Entities

- **Player**: Represents a registered participant. Attributes: full name, date of birth, gender/category (Male or Female — see FR-014), email, mobile number (stored E.164-normalized), profile picture, username (unique), location/town, region (one of 8), preferred venue (reference to a preloaded Venue, or a free-text "other" value), notification preference (Email/SMS/Both), team reference (nullable, at most one), region-locked flag (derived from existence of a `Match Result`, spec 008 — not from fixture/draw existence), hashed password, timestamps.
- **Region**: One of the 8 fixed league regions a player belongs to.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new visitor can complete registration end-to-end (form submit to confirmation received) in under 2 minutes on a standard mobile browser.
- **SC-002**: 100% of registration attempts with age under 18 are rejected in testing; 100% of attempts with a duplicate username are rejected.
- **SC-003**: The system correctly accepts concurrent registration bursts (e.g., simulated regional registration windows opening) with standard page responses remaining under 2 seconds.
- **SC-004**: 100% of players who have at least one recorded match are blocked from changing their region in testing.

## Assumptions

- Profile picture constraints (max file size, accepted formats) will be defined as a concrete configuration value during implementation planning; the requirement itself (a picture is required/allowed) is in scope, exact limits are not yet fixed. Per the design system's bandwidth guidance (NFR-8.2), uploads should be server-side resized/compressed rather than stored at original resolution.
- Username uniqueness is assumed case-insensitive by default (common practice) unless clarified otherwise.
- Player authentication (login/session) reuses the same general session-based approach as admin authentication (spec 001) but with entirely separate credentials and session storage, per NFR-4.2's role separation intent (applied here to player-vs-admin, not player-vs-player).
- The "venue preference" captured here is a general profile preference only, not tied to any specific match or draw (per scope doc §5.3).
- Region-lock (FR-008) is keyed to spec 008's `Match Result` entity, not spec 007's `Fixture` entity — this makes spec 003 dependent on spec 008's schema existing (or at least being stubbed) before the lock check can be implemented; sequence accordingly when building `tasks.md`.
- Treating `gender` as a two-value, competition-category-determining field (FR-014) is a scope-narrowing default chosen to keep every player unambiguously assignable to a standings category. It is flagged prominently (see Edge Cases) because it is a data-governance decision, not just a UI one, and should be confirmed rather than silently built.
- E.164 mobile number normalization (FR-013) assumes Kenya (`+254`) as the default country for numbers without an explicit country code, consistent with the product's target market; a player entering a foreign number with its own country code is still accepted as long as it normalizes to a valid E.164 value.
