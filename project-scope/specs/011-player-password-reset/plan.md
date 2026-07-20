# Implementation Plan: Player Password Reset

**Branch**: `011-player-password-reset` | **Date**: 2026-07-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-player-password-reset/spec.md`

## Summary

Add a self-service reset flow behind the already-shipped `/forgot-password` and `/reset-password/:token` LiveViews (previously design-only stubs): requesting a link looks up the player without revealing account existence, issues a hashed, 20-minute single-use token reusing the existing `player_tokens` table (`context: "reset_password"`), and delivers it via a dedicated Oban worker/email — deliberately bypassing the `Notifications` dispatch pipeline (spec 002), since that pipeline fans out by stored channel preference and persists its payload into the admin-visible Notification Log, neither of which is appropriate for a live reset credential. Completing the reset validates the token, enforces the existing `PasswordValidator` policy, and invalidates every session token the player has.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix/LiveView 1.8, `Swoosh` (email, reusing `Cuevolution.Mailer` and the `layout/2`+`button/2` helpers already in `Cuevolution.Notifications.Emails`), `Oban` (async send/retry, reusing the `:notifications` queue), `Bcrypt`/`:crypto` (token hashing — `:crypto.hash(:sha256, ...)`, distinct from password hashing)

**Storage**: PostgreSQL — no new tables/migrations. Reuses `player_tokens` (from spec 003, `20260709215731_create_player_tokens.exs`) with a new `context` value, `"reset_password"`, alongside the existing `"session"`. Unlike the session context (raw token bytes, never exposed outside a signed cookie), the reset token is hashed at rest (`sha256`) since it's transmitted over email — the raw value is emailed, only the hash is stored, mirroring `phx.gen.auth`'s approach to reset/confirmation tokens.

**Testing**: ExUnit, `Swoosh.TestAssertions` (`assert_email_sent`/`refute_email_sent`, matching `send_email_worker_test.exs`), `Oban.Testing` (`assert_enqueued`), `Phoenix.LiveViewTest` for the two LiveViews end to end

**Target Platform**: Server-side, same release as the rest of the web app

**Performance Goals**: Reset request enqueues the email send within the triggering request (same pattern as registration's confirmation email) so `/forgot-password` never blocks on Postmark; actual delivery happens async via Oban

**Constraints**: The raw reset token must never be written to the admin-visible `notifications.payload` column (FR-003/edge case in spec.md) — this is why delivery is a standalone worker rather than a new `Notifications.dispatch/3` event type. The token must be single-use and hashed at rest (FR-006/FR-009).

**Scale/Scope**: One event, two LiveViews already scaffolded, no new tables.

## Constitution Check

*No formal `constitution.md` exists yet. Gates carried over from this feature's spec and from spec 002/003's precedent:*

- FR-002 (no account-existence leak): **gate** — `ForgotPasswordLive` transitions to the "check your email" stage unconditionally; a test asserts the same HTML renders for a known vs. unknown login, and `refute_email_sent/1` for the unknown case.
- FR-003 (email-only, ignores `notification_preference`): **gate** — the new worker/email path never reads `Player.notification_preference` or calls `Notifications.dispatch/3`; a test registers a player with `notification_preference: "sms"` and confirms the reset email still sends.
- FR-004/FR-006 (20-minute, single-use, hash-tolerant rejection): **gate** — `PlayerToken.verify_reset_password_token_query/1` is tested against an expired token, a token already consumed by a completed reset, and a garbage (non-base64 or never-issued) string, asserting all three land on the same "invalid" outcome.
- FR-008 (full session invalidation on reset): **gate** — a test creates a session token for a player, resets their password, and asserts `get_player_by_session_token/1` on the old token now returns `nil`.
- FR-009 (hashed at rest): **gate** — a test inserts a reset token and asserts the persisted `player_tokens.token` bytes do not equal the raw emailed value.

## Project Structure

### Documentation (this feature)

```text
specs/011-player-password-reset/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── accounts.ex                                        # + get_player_by_login/1, deliver_player_reset_password_instructions/2,
│                                                       #   get_player_by_reset_password_token/1, reset_player_password/2
├── accounts/
│   ├── player.ex                                      # + :password_confirmation virtual field, reset_password_changeset/2
│   └── player_token.ex                                # + build_reset_password_token/1, verify_reset_password_token_query/1
└── notifications/
    ├── emails.ex                                      # + reset_password_instructions/2
    └── workers/
        └── send_password_reset_email_worker.ex        # new — standalone, not through Notifications.dispatch/3

lib/cuevolution_web/
├── router.ex                                           # "/reset-password" -> "/reset-password/:token"
└── live/player/
    ├── forgot_password_live.ex + .html.heex            # real lookup/deliver, drop "Open reset link" shortcut
    └── reset_password_live.ex + .html.heex              # real token verification, :invalid stage, changeset-driven form

test/cuevolution/
├── accounts_test.exs                                   # + reset-flow cases
├── accounts/player_token_test.exs                       # new
└── notifications/workers/send_password_reset_email_worker_test.exs   # new

test/cuevolution_web/live/
├── forgot_password_live_test.exs                        # new
└── reset_password_live_test.exs                         # new
```

**Structure Decision**: Single Phoenix application, no new context. Everything lives in the existing `Accounts` context (owns `Player`/`PlayerToken`, same as session auth) plus one new worker/email function in the existing `Notifications` namespace — deliberately *not* a new `Notifications.dispatch/3` event type, per the Constitution Check gates above.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
