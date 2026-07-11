# Feature Specification: Admin Authentication & Access Control

**Feature Branch**: `001-admin-authentication`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.8 Admin) and `requirements/cuevolution-requirements.md` (FR-9.1–FR-9.3, NFR-4.1, NFR-4.2, NFR-9.1)

**Traceability**: FR-9.1, FR-9.2, FR-9.3, NFR-4.1, NFR-4.2, NFR-9.1

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin logs in to a distinct admin area (Priority: P1)

A league administrator needs to sign in using credentials that are entirely separate from player accounts, landing in an admin-only area of the application where they can manage regions, venues, players, teams, draws, results, and points.

**Why this priority**: Every other admin-facing feature (venues, draws, results, points, standings maintenance) depends on a working, secure admin login. Without it, no admin capability in any other spec can be exercised.

**Independent Test**: Can be fully tested by attempting to log in with valid admin credentials and confirming access to an admin landing page, independent of any other feature being built yet.

**Acceptance Scenarios**:

1. **Given** a valid admin account exists, **When** the admin submits correct email/username and password on the admin login page, **Then** they are authenticated and redirected to the admin dashboard.
2. **Given** a valid admin account exists, **When** the admin submits an incorrect password, **Then** the system rejects the attempt with a generic error message and does not reveal whether the email or password was wrong.
3. **Given** an admin is logged in, **When** they select "log out", **Then** their session is invalidated and subsequent requests to admin pages redirect to the login page.

---

### User Story 2 - Player accounts cannot access admin functionality (Priority: P1)

A regular player who is logged into their player account must never be able to reach admin-only pages or perform admin-only actions (managing venues, entering draws/results/points, editing another player's data), even by guessing a URL.

**Why this priority**: This is the core access-control guarantee (NFR-4.2) that every other feature's admin-only requirements (FR-3.1, FR-5.1, FR-6.1, FR-6.4, etc.) depend on. A gap here is a security failure, not a missing convenience.

**Independent Test**: Can be tested by authenticating as a player (once player accounts exist) or as an anonymous visitor and attempting to navigate directly to any admin route, confirming access is denied/redirected in every case.

**Acceptance Scenarios**:

1. **Given** no one is logged in, **When** an anonymous visitor requests any admin route, **Then** they are redirected to the admin login page.
2. **Given** a player is logged into their player account, **When** they request an admin route, **Then** access is denied and they are not shown any admin data or controls.
3. **Given** an admin is logged in, **When** they request a player-only route that requires a player session, **Then** the system treats them as not having a player session (admin and player sessions are distinct and do not implicitly grant each other's access).

---

### User Story 3 - Admin actions are auditable (Priority: P2)

The league needs a record of who performed key administrative actions (draw entry, results entry, points entry) so that disputes or data-entry errors can be traced back to an admin action and timestamp.

**Why this priority**: Supports operational trust and troubleshooting once the system is live, but the system is still usable for initial rollout without it — it does not block the core login/access-control loop.

**Independent Test**: Can be tested by performing an admin login and one logged action (even a placeholder action if other features aren't built yet) and confirming an audit record is created with admin identity and timestamp.

**Acceptance Scenarios**:

1. **Given** an admin is logged in, **When** they perform a logged action type (e.g., draw entry, results entry, points entry), **Then** a record is stored capturing which admin performed it and when.
2. **Given** an admin corrects an already-entered result or points value (spec 008), **When** the correction is saved, **Then** the audit record captures both the prior and new value, not just the fact that a correction occurred — a log entry that can't answer "what did it change from and to" doesn't resolve the disputes this feature exists for.

---

### Edge Cases

- What happens when an admin's password needs to be reset (no self-service player-style signup exists for the single admin role)? [NEEDS CLARIFICATION: password reset/recovery process for the admin account is not specified — is it a manual/ops-level reset, or a self-service "forgot password" email flow?]
- What happens after repeated failed login attempts — is there rate limiting or lockout? **Explicitly deferred** — rate limiting/throttling is intentionally out of scope for this MVP (confirmed product decision, not an oversight); revisit if the single admin account becomes a credential-stuffing target once the platform is public.
- How is the initial admin account created, since there is no admin self-registration flow? [NEEDS CLARIFICATION: assumed to be a one-time seed/provisioning step outside the public UI]
- What happens if an admin session is active in two browser tabs/devices simultaneously — is concurrent admin login permitted? **Allowed for MVP** (no session-exclusivity requirement is stated), which is exactly the scenario that motivates the concurrency-safety fixes applied to stage-capacity checks (spec 006) and the one-team-per-player guard (spec 005) — the admin having two tabs open is treated as a normal case to design against, not an edge case to prevent.
- **Single admin as a single point of failure** [New, from system design review §3]: distinct from the "no multi-admin roles" scope decision — there is currently no recovery path if the one admin's credential is lost mid-tournament (forgotten password with no reset flow, per the item above, plus no second account to fall back on). Recommend an operational mitigation outside the application itself (e.g., the credential is stored in a shared secrets manager accessible to more than one trusted person), since building a second in-app role is explicitly out of scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an admin authentication mechanism that is entirely distinct from player account authentication (separate credentials, separate session).
- **FR-002**: The system MUST restrict access to all admin capabilities (managing regions, venues, players, teams, draws, results, and points) to authenticated admin sessions only.
- **FR-003**: The system MUST reject unauthenticated or player-authenticated requests to any admin-only route or action.
- **FR-004**: The system MUST support a single admin role for the MVP (no regional or tiered admin roles).
- **FR-005**: The system MUST log key admin actions (at minimum: draw entry, results entry, points entry, and any correction to a previously entered result/points value) including which admin performed the action, when, and — for corrections — both the prior and new value.
- **FR-006**: The system MUST store admin credentials using an industry-standard salted hashing algorithm (e.g., bcrypt or argon2), never in plaintext.
- **FR-007**: The system MUST allow an admin to log out, invalidating their current session.

### Key Entities

- **Admin**: A single privileged account type representing the league administrator. Attributes: identifier (email or username), hashed password, timestamps. Not linked to a Player record.
- **Admin Session**: Represents an authenticated admin browser session, distinct from a Player session.
- **Admin Action Log**: A record of a significant admin action, capturing the admin identity, the action type (e.g., draw entered, result entered, points entered, result corrected, points corrected), the affected entity, a prior-value/new-value snapshot (populated for correction actions, null for first-time entries), and a timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of requests to admin-only pages/actions from anonymous or player-authenticated sessions are denied in testing (zero privilege-escalation gaps).
- **SC-002**: An admin can complete login and reach the admin dashboard in under 5 seconds under normal network conditions.
- **SC-003**: Every draw-entry, results-entry, and points-entry action performed during a test pass has a corresponding audit log entry with correct admin identity and timestamp.
- **SC-004**: 100% of correction actions (result or points) logged during testing include both the prior and new value, readable without cross-referencing another table.

## Assumptions

- Exactly one admin account is provisioned for MVP (no multi-admin management UI is required, per the "single admin role" scope decision).
- The initial admin account is created via a manual/ops step (e.g., a seed script or database insert), not through a public sign-up form, since admin self-registration is explicitly out of scope.
- Admin password reset is handled operationally (e.g., by whoever manages deployment) rather than via a self-service email flow, unless clarified otherwise later.
- Rate limiting/login throttling is an intentional MVP exclusion per explicit product direction, not a gap — noted here so it isn't mistaken for an oversight during implementation review.
- "Admin action log" is an append-only record sufficient for audit/troubleshooting; it now includes a prior/new value snapshot for correction-type actions (system design review §2.6) but is still not a full point-in-time revision history of every field on every entity — only the specific fields corrections target (results, points, and this spec's own scope).
