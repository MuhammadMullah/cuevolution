# Feature Specification: Player Password Reset

**Feature Branch**: `011-player-password-reset`

**Created**: 2026-07-17

**Status**: Draft

**Input**: Not present in `requirements/cuevolution-requirements.md` or `requirements/cuevolution-scope.md` — this extends spec 003's FR-011 ("the system MUST authenticate players via credentials... with passwords stored using an industry-standard salted hash"), which specifies password storage but never a recovery path for a forgotten one. Raised directly by the product owner alongside a design update to the sign-in/registration screens (a repeating background pattern) that also introduced this journey's mockup states.

**Traceability**: Extends FR-011 (spec 003); depends on spec 002's `Notifications`/`Swoosh` mail infrastructure for delivery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player requests a password reset link (Priority: P1)

A player who has forgotten their password enters the email or username on their account from the sign-in page, and — regardless of whether that login actually matches an account — sees a "check your email" confirmation. If it did match, an email arrives with a link to set a new password.

**Why this priority**: Without this, a player who forgets their password is permanently locked out of their account with no self-service recovery path, and the only escape hatch is manual/ops intervention (the exact gap flagged, for the *admin* account, as a `[NEEDS CLARIFICATION]` in spec 001). This is the entry point for the whole feature.

**Independent Test**: Can be fully tested by submitting a known player's email/username on `/forgot-password` and confirming a reset email is enqueued/sent, independent of the reset-completion step (User Story 2) being exercised.

**Acceptance Scenarios**:

1. **Given** a visitor is on `/login`, **When** they select "Forgot password?", **Then** they land on a form asking for their email or username.
2. **Given** the visitor submits the email/username of an existing player, **When** the form is submitted, **Then** a reset-password email is sent to that player's registered email address, and the page shows a "check your email" confirmation.
3. **Given** the visitor submits a login that matches no player, **When** the form is submitted, **Then** the page shows the exact same "check your email" confirmation as a match would (no email is actually sent) — the system MUST NOT reveal whether a given email/username is registered.
4. **Given** the visitor submits an empty field, **When** they try to submit, **Then** the form is rejected inline without a "check your email" transition.
5. **Given** a player is on the "check your email" screen, **When** they select "Resend email", **Then** a new attempt is made against the same login (silently a no-op if it didn't match an account, per Scenario 3).

---

### User Story 2 - Player completes the reset via the emailed link (Priority: P1)

A player who received the reset email clicks its link, lands on a "choose a new password" form, submits a new password meeting the account password policy, and can immediately sign in with it.

**Why this priority**: User Story 1 alone doesn't unlock the account — the player needs to actually be able to set a new password for this feature to solve the underlying "I'm locked out" problem. Equal priority to Story 1; the feature has no value with only one half built.

**Independent Test**: Can be tested by generating a valid reset token directly (bypassing Story 1's email step) and completing the form, confirming the password changes and old sessions/tokens are invalidated.

**Acceptance Scenarios**:

1. **Given** a player follows a valid, unexpired reset link, **When** they submit a new password meeting the password policy (spec 003/`PasswordValidator`: 8-15 chars, upper-case, digit, special character) and matching confirmation, **Then** the password is updated and they see a success screen.
2. **Given** a player follows a reset link, **When** the new password fails policy validation or the confirmation doesn't match, **Then** the form is rejected inline with field-level errors, without invalidating the link.
3. **Given** a player follows a reset link more than 20 minutes after it was requested, **When** they view the page, **Then** they're shown an "invalid or expired link" state rather than the password form.
4. **Given** a player follows a reset link that has already been used to successfully reset the password once, **When** they view the page again, **Then** it is treated as invalid (single-use).
5. **Given** a player successfully resets their password, **When** the reset completes, **Then** every existing session for that player (including the one that requested the reset, if logged in elsewhere) is invalidated, requiring sign-in with the new password everywhere.

---

### Edge Cases

- What happens if two reset links are requested for the same player before either is used? **Resolved**: requesting a new link invalidates any earlier unused one for that player — only the most recently requested link is valid, closing the window where an old, possibly-intercepted email link stays live indefinitely.
- What happens if the token in the URL is tampered with or simply garbage (not a value this system ever issued)? **Resolved**: treated identically to an expired link ("invalid or expired") — the system doesn't distinguish "malformed" from "expired" in its response, so probing doesn't leak which case occurred.
- Should the reset email be affected by the player's `notification_preference` (Email/SMS/Both, spec 003)? **Resolved**: no — password reset always goes by email regardless of stored preference, since it is a security-sensitive link rather than a routine notification, and delivering a clickable reset link over SMS is out of scope.
- Should a password reset attempt be visible to admins in the Notification Log (spec 002, User Story 3)? **Resolved — explicitly deferred, not an oversight**: it is not. That log's payload column is admin-browsable, and a live reset credential must not be persisted anywhere an admin can read it back out. Revisit only if a genuinely payload-free audit trail (e.g., just a timestamp + player id, no token) becomes a real operational need.
- What happens to a player's other active sessions when they reset their password from one device? **Resolved — see Acceptance Scenario 2.5**: all sessions are invalidated, not just the one on the device used to reset.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST let a player request a password reset by submitting their registered email or username.
- **FR-002**: The system MUST respond identically (a "check your email" confirmation) whether or not the submitted login matches an existing player — it MUST NOT reveal account existence.
- **FR-003**: The system MUST email a single-use reset link only to the matched player's registered email address when a match exists, regardless of that player's stored notification preference.
- **FR-004**: The reset link MUST expire 20 minutes after it is requested.
- **FR-005**: Requesting a new reset link for a player MUST invalidate any previously issued, unused reset link for that same player.
- **FR-006**: The system MUST reject an expired, already-used, or malformed/tampered reset token with the same "invalid or expired" outcome, without distinguishing between those cases in the response.
- **FR-007**: The system MUST enforce the same password policy on a reset password as on registration (spec 003 `PasswordValidator`: 8-15 characters, at least one upper-case letter, one digit, one special character) and require a matching confirmation value.
- **FR-008**: A successful password reset MUST invalidate every existing session token for that player, not only the reset token used.
- **FR-009**: The reset token MUST be stored hashed, not in plaintext, so that database read access alone is insufficient to reconstruct a usable reset link.

### Key Entities

- **Player** (spec 003): unchanged shape: this feature only ever updates `hashed_password`.
- **Player Token** (spec 003/existing `player_tokens` table): reused as-is, gains a new `context: "reset_password"` value alongside the existing `"session"` context. Attributes relevant here: the token value (hashed for this context, unlike the raw session token), owning player, `sent_to` (the email the link was sent to), issued-at (used to compute the 20-minute expiry).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of reset requests for a non-existent login show the same confirmation screen as a match, in testing (no observable difference in response shape or timing budget).
- **SC-002**: 100% of reset links older than 20 minutes, already used, or malformed are rejected in testing.
- **SC-003**: A player can go from "forgot my password" to "signed in with a new one" without any manual/ops intervention, in under 3 minutes under normal conditions (mail delivery included).
- **SC-004**: 100% of successful resets in testing invalidate every prior session token for that player.

## Assumptions

- The password policy is exactly spec 003's existing `Cuevolution.Accounts.PasswordValidator` (8-15 chars, upper-case + digit + special character) — no separate, weaker or stronger policy for resets.
- 20 minutes is a product-confirmed default for this MVP, chosen as a common industry baseline for password-reset link exposure windows; revisit if support feedback shows players routinely missing that window.
- This spec covers **player** password reset only. Admin password reset remains the `[NEEDS CLARIFICATION]` open item noted in spec 001 and is out of scope here.
- Rate-limiting reset requests (e.g., someone spamming the form for a given login) is not addressed by this spec, consistent with spec 001's explicit MVP exclusion of login-attempt rate limiting generally — noted here so it isn't mistaken for an oversight.
