# Feature Specification: Notifications Infrastructure

**Feature Branch**: `002-notifications-infrastructure`

**Created**: 2026-07-07

**Status**: Draft

**Input**: Derived from `requirements/cuevolution-scope.md` (§5.7 Notifications, §7.1, §7.3) and `requirements/cuevolution-requirements.md` (FR-8.1–FR-8.4, NFR-3.2, NFR-5.3, NFR-7.1, NFR-9.2)

**Traceability**: FR-8.1, FR-8.2, FR-8.3, FR-8.4, NFR-3.2, NFR-5.3, NFR-7.1, NFR-9.2

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player receives a registration confirmation (Priority: P1)

When a player completes registration, they receive a confirmation through the channel(s) they selected (Email, SMS, or both), reassuring them their account was created successfully.

**Why this priority**: This is the very first notification a user ever receives and the simplest possible end-to-end proof that the notification pipeline (preference lookup → channel dispatch → delivery) works, before any other event type is layered on.

**Independent Test**: Can be tested by triggering the "registration confirmed" event for a test player with each of the three preference values (Email, SMS, Both) and confirming the correct channel(s) fire, independent of the draw/fixture feature existing yet.

**Acceptance Scenarios**:

1. **Given** a player registered with preference "Email", **When** the registration-confirmation event fires, **Then** an email is sent and no SMS is attempted.
2. **Given** a player registered with preference "SMS", **When** the registration-confirmation event fires, **Then** an SMS is sent via the SMS adapter and no email is attempted.
3. **Given** a player registered with preference "Both", **When** the registration-confirmation event fires, **Then** both an email and an SMS are sent.

---

### User Story 2 - Player receives a draw/fixture assignment notification (Priority: P1)

When the admin enters or edits a draw, every affected player/team receives a notification stating who they play, where, and when.

**Why this priority**: This is the notification event with the most operational importance — players who miss a fixture because they weren't notified is a direct tournament-integrity failure. It's tied for P1 with registration confirmation because both are named as MVP-required events (FR-8.3).

**Independent Test**: Can be tested by invoking the notification-dispatch function with a synthetic fixture payload (opponent, venue, date, time) for a recipient with a known preference, independent of the full draws UI (spec 007) being complete — the draws feature will call into this dispatch capability once built.

**Acceptance Scenarios**:

1. **Given** a draw entry is created assigning Player A vs Player B at a venue/date/time, **When** the draw is saved, **Then** both Player A and Player B receive a notification containing opponent name, venue, date, and time via their respective preferences.
2. **Given** a draw entry is later edited (opponent, venue, date, or time changes), **When** the edit is saved, **Then** both affected participants receive an updated notification reflecting the new details.

---

### User Story 3 - Admin can see notification delivery status for troubleshooting (Priority: P2)

The admin needs to see whether a given notification actually reached the player, so that if a player claims they "never got the fixture," the admin can check whether it was sent, failed, or is still pending/retrying.

**Why this priority**: Important operational visibility, but the system already delivers value (sending notifications) without this view — it's a troubleshooting aid, not a blocker to the core send path.

**Independent Test**: Can be tested by sending a batch of notifications with a mix of simulated success/failure outcomes and confirming an admin-visible log reflects accurate status per notification, independent of any specific event type's UI.

**Acceptance Scenarios**:

1. **Given** a notification was sent successfully, **When** the admin views the notification log, **Then** it shows a "delivered/sent" status with a timestamp.
2. **Given** a notification attempt failed (e.g., SMS provider timeout), **When** the admin views the notification log, **Then** it shows a "failed" status with error detail and any retry attempts made.

---

### Edge Cases

- What happens when SMS sending fails transiently (provider timeout)? The system retries with failure logged rather than silently dropping (NFR-3.2). [NEEDS CLARIFICATION: retry count/backoff schedule not specified]
- What happens when a player's email address or mobile number is invalid/malformed at send time?
- What happens when a player has preference "Both" and one channel succeeds while the other fails — is this a partial-success state?
- What happens when the SMS provider integration itself is unreachable (not just a single message failing)?
- How are notification events tied to consent — e.g., contact info must only be used for the notification purposes the player consented to at registration (NFR-5.3), not repurposed for other messaging.
- **Duplicate sends on retry** [Resolved — see FR-009]: identified in system design review §2.2 — if a send actually succeeds but the process crashes before the delivery-status row is marked `sent`, an Oban retry (which re-runs the whole job) could resend the same message. Guarded by an idempotency key rather than trusting "the job hasn't been marked done yet" as a proxy for "the message hasn't been sent yet."
- **Opponent contact-info leakage** [Resolved — see FR-010]: a fixture-assignment notification must never include the opponent's email or mobile number, only their name — this is a dispatch-layer constraint enforced here since spec 007 (draws) is the caller, not the one responsible for redacting payloads.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST send a notification via Email, SMS, or both, based on the recipient's currently stored notification preference.
- **FR-002**: The system MUST send a notification for a "registration confirmed" event upon successful player registration.
- **FR-003**: The system MUST send a notification for a "fixture assigned" event whenever a draw entry is created or edited for a participant, containing opponent, venue, date, and time.
- **FR-004**: The system MUST send SMS through a swappable adapter/interface layer that is decoupled from any specific SMS provider implementation, so the provider can be changed without changing calling code.
- **FR-005**: The system MUST log the delivery status (e.g., pending, sent, failed) of every notification attempt, per channel, for admin review.
- **FR-006**: The system MUST retry a notification send on transient failure (e.g., provider timeout) rather than silently dropping it, and MUST log the outcome of each retry attempt.
- **FR-007**: The system MUST use recipient contact information (email, mobile number) only for the notification purposes the recipient consented to at registration.
- **FR-008**: The system MUST expose a single, reusable dispatch capability that other features (registration, draws) call with an event type and recipient rather than implementing channel logic themselves.
- **FR-009**: Each notification send attempt MUST be keyed by a stable idempotency key (e.g., recipient + event type + source record + channel), and a retried send MUST check that key before contacting the provider a second time, so a crash between a successful provider call and the delivery-status write cannot result in a duplicate message reaching the recipient.
- **FR-010**: The dispatch capability MUST reject or strip any payload field that exposes another person's contact information (email, mobile number) — notification content may name another participant (e.g., an opponent) but must never include their contact details.

### Key Entities

- **Notification**: A record of one attempted message to one recipient. Attributes: recipient reference, event type (e.g., registration_confirmation, fixture_assignment), source record reference (e.g., the fixture or registration that triggered it), idempotency key (unique), channel (email/sms), status (pending/sending/sent/failed), error detail (if any), retry count, timestamps.
- **SMS Adapter (behaviour/interface)**: A contract that any concrete SMS provider integration must implement (e.g., `send/2` returning success/failure), allowing the underlying provider to be swapped without touching dispatch logic.
- **Notification Preference** *(owned by the Accounts/Player entity, referenced here)*: The recipient's chosen channel(s) — Email, SMS, or Both — read at dispatch time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of successful player registrations during testing produce a confirmation notification matching the player's selected channel(s).
- **SC-002**: 100% of draw entries/edits during testing produce a fixture notification to every affected participant, with correct opponent/venue/date/time.
- **SC-003**: Every notification attempt (success or failure) has a corresponding, admin-visible log entry with accurate status.
- **SC-004**: A transient send failure results in at least one automatic retry before being marked failed, with no notification silently disappearing (zero unlogged attempts).
- **SC-005**: A simulated crash between a successful provider call and the delivery-status write, followed by a retry, results in zero duplicate messages reaching the recipient in testing.
- **SC-006**: 100% of fixture-assignment notification payloads inspected during testing contain the opponent's name only, with no email or mobile number field present.

## Assumptions

- SMS provider selection is deferred (per scope doc §9); the adapter is built against a well-defined internal behaviour, with a stub/test implementation standing in for a real provider until one is chosen.
- "Both" preference sends both channels independently; a failure on one channel does not block or roll back the other.
- Notification content templates (exact wording) are an implementation detail decided during development, not specified by the business requirements.
- Delivery-status logging is for admin troubleshooting only in MVP — there is no player-facing "delivery receipt" UI.
- The idempotency key (FR-009) is a deterministic composite (recipient + event type + source record id + channel) rather than a randomly generated token, so that re-dispatching the *same* logical event (e.g., re-processing a queued job after a crash) is naturally detected without needing external state beyond the `notifications` table itself.
