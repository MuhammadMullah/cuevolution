# Implementation Plan: Notifications Infrastructure

**Branch**: `002-notifications-infrastructure` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-notifications-infrastructure/spec.md`

## Summary

Build a `Notifications` context that exposes a single dispatch entry point (event type + recipient), fans out to Email and/or SMS based on the recipient's stored preference, sends SMS through a swappable adapter behaviour, retries transient failures, and logs delivery status for every attempt. Player registration (spec 003) and draws (spec 007) call into this context rather than implementing channel logic themselves.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, `Swoosh` (email delivery), `Oban` (background job processing for async send + retry with backoff), a custom `Cuevolution.Notifications.SmsAdapter` behaviour with a stub adapter for MVP (real provider TBD per scope doc §9)

**Storage**: PostgreSQL — `notifications` table (delivery log, with a unique `idempotency_key` column per FR-009) — the unique constraint is what makes retries safe: the worker upserts on `idempotency_key`, moving the row to `sending` *before* calling the provider, so a crash-and-retry finds the existing row already past `pending` and skips a second provider call rather than relying on Oban's own job state as the source of truth; Oban's own job tables for retry/queueing

**Testing**: ExUnit, `Swoosh.TestAssertions` for email, a mock SMS adapter (via `Mox`) implementing the `SmsAdapter` behaviour for deterministic tests, `Oban.Testing` for job assertions

**Target Platform**: Server-side background processing within the same Elixir release as the web app

**Performance Goals**: Notification dispatch enqueued within the same request/transaction that triggers it (registration, draw save), actual send happens asynchronously so it never blocks the triggering page response (supports NFR-1.1's <2s page target)

**Constraints**: SMS sending must go through the adapter behaviour only — no direct provider SDK calls from calling contexts (NFR-7.1); failed sends must retry and log, never silently drop (NFR-3.2)

**Scale/Scope**: Two MVP event types (registration confirmation, fixture assignment); designed so additional event types can be added as new callers of the same dispatch function without changing the dispatch/retry/logging core

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-7.1: SMS integration MUST be a swappable adapter/behaviour — **gate**: no module outside `Cuevolution.Notifications` may reference a concrete SMS provider.
- NFR-3.2: transient failures retried with logging, not silently dropped — **gate**: every send path goes through an Oban worker with a configured retry/backoff strategy and a logged terminal state.
- NFR-5.3: contact info used only for consented purposes — **gate**: dispatch only reads the recipient's stored preference and contact fields; no ad-hoc messaging paths.
- NFR-9.2: basic monitoring suitable for spotting delivery failures — **gate**: failed/exhausted-retry notifications are queryable/log-visible for the admin (User Story 3).
- FR-009/SC-005: retries must not duplicate a successful send — **gate**: a test that simulates a crash after the provider call but before the status write, then re-runs the job, and asserts the mock adapter/mailer was invoked exactly once.
- FR-010/SC-006: no contact-info leakage in payloads — **gate**: `dispatch/3` validates the payload map against an allowlist of safe keys per event type before handing off to a worker; a payload containing `opponent_email`/`opponent_mobile_number` is rejected at the `dispatch/3` boundary, not left to the caller's discipline.

## Project Structure

### Documentation (this feature)

```text
specs/002-notifications-infrastructure/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── notifications.ex                      # Context: dispatch(event_type, recipient, payload)
├── notifications/
│   ├── notification.ex                   # Ecto schema: notifications table (delivery log)
│   ├── sms_adapter.ex                    # @behaviour definition (send/2)
│   ├── sms_adapter/
│   │   └── stub_adapter.ex               # MVP stub implementation (logs instead of real send)
│   ├── mailer.ex                         # Swoosh mailer setup
│   ├── emails/
│   │   ├── registration_confirmation_email.ex
│   │   └── fixture_assignment_email.ex
│   └── workers/
│       ├── send_email_worker.ex          # Oban worker: send + record status
│       └── send_sms_worker.ex            # Oban worker: send via adapter + record status

lib/cuevolution_web/
└── live/
    └── admin/
        └── notification_log_live.ex      # Admin-visible delivery status view (User Story 3)

priv/repo/migrations/
└── ..._create_notifications.exs

test/cuevolution/notifications_test.exs
test/cuevolution/notifications/workers/send_email_worker_test.exs
test/cuevolution/notifications/workers/send_sms_worker_test.exs
test/support/notifications/mock_sms_adapter.ex
```

**Structure Decision**: Single Phoenix application. `Notifications` is its own top-level context per NFR-7.2, with no direct dependency from `Accounts` or `Competitions` on any specific email/SMS library — those contexts only call `Cuevolution.Notifications.dispatch/3`.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
