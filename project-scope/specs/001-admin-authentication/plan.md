# Implementation Plan: Admin Authentication & Access Control

**Branch**: `001-admin-authentication` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-admin-authentication/spec.md`

## Summary

Provide a standalone admin authentication system (login, session, logout) that is fully separate from player authentication, enforce role-based access control on all admin routes, and record an audit log entry for key admin actions. This feature is foundational — venue management, draws, results/points entry, and qualification-stage management all sit behind the RBAC gate built here.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView, `phx.gen.auth`-style scoped authentication (adapted for a second, admin-scoped identity), Ecto, bcrypt_elixir (or argon2_elixir) for password hashing

**Storage**: PostgreSQL — `admins`, `admin_tokens`, `admin_action_logs` tables

**Testing**: ExUnit, `Phoenix.LiveViewTest`, `Plug.Test` for pipeline/authorization tests

**Target Platform**: Server-rendered web (Phoenix LiveView), deployed as an Elixir release

**Project Type**: Web application (single Phoenix umbrella-less app, `lib/cuevolution` + `lib/cuevolution_web`)

**Performance Goals**: Admin login round trip under 2s (NFR-1.1 general page-response target)

**Constraints**: Admin and player sessions must never share a session token or implicitly grant each other's access (hard isolation requirement from FR-002/FR-003 of this spec)

**Scale/Scope**: Single admin account for MVP; RBAC gate reused by every other admin-facing feature

## Constitution Check

*No formal `constitution.md` exists yet for this project. In its absence, the following requirements from `requirements/cuevolution-requirements.md` act as non-negotiable gates for this feature:*

- NFR-4.1: credentials hashed with bcrypt/argon2, never plaintext — **gate**: no plaintext password storage or logging.
- NFR-4.2: admin functionality protected by RBAC, inaccessible to player accounts — **gate**: every admin LiveView/route is mounted behind an admin-only plug/`on_mount` hook, verified by tests in User Story 2.
- NFR-9.1: key admin actions logged for audit — **gate**: draw/results/points entry (built in later features) must call a shared audit-logging function introduced here.
- FR-005/SC-004: corrections logged with prior + new value — **gate**: `log_admin_action/4`'s `prior_value`/`new_value` options are populated by every caller performing a correction (spec 008's `correct_result/2`, `correct_points/2`; spec 005's roster-freeze override), not just a generic "something changed" entry.
- NFR-7.2: Phoenix context boundaries kept decoupled — **gate**: admin identity lives in the `Accounts` context alongside (but structurally separate from) player identity; no cross-context field sharing.

## Project Structure

### Documentation (this feature)

```text
specs/001-admin-authentication/
├── plan.md              # This file
└── spec.md              # Feature specification
```

### Source Code (repository root)

```text
lib/cuevolution/
├── accounts/
│   ├── admin.ex              # Ecto schema: admins table
│   ├── admin_token.ex        # Ecto schema: admin_tokens table (session/remember-me tokens)
│   └── admin_action_log.ex   # Ecto schema: admin_action_logs table
├── accounts.ex                # Context: admin registration (seed-only), authenticate_admin/2,
│                               #          generate_admin_session_token/1,
│                               #          log_admin_action/4 (action_type, admin, entity, opts \\ [prior_value: nil, new_value: nil])

lib/cuevolution_web/
├── live/
│   └── admin/
│       ├── admin_login_live.ex        # Admin login form (LiveView)
│       └── admin_dashboard_live.ex    # Minimal landing page after login
├── controllers/
│   └── admin_session_controller.ex    # Plug-based session create/delete (mirrors phx.gen.auth pattern)
├── plugs/
│   └── admin_auth.ex                  # fetch_current_admin / require_admin plugs + LiveView on_mount hook
└── router.ex                          # :admin_browser pipeline + live_session requiring admin

priv/repo/migrations/
├── ..._create_admins.exs
├── ..._create_admin_tokens.exs
└── ..._create_admin_action_logs.exs   # includes prior_value/new_value jsonb columns (nullable; populated for corrections)

test/cuevolution/accounts_test.exs
test/cuevolution_web/live/admin/admin_login_live_test.exs
test/cuevolution_web/plugs/admin_auth_test.exs
```

**Structure Decision**: Single Phoenix application (no umbrella). Admin identity is modeled as its own schema (`Admin`) inside the shared `Accounts` context rather than a new top-level context, since NFR-7.2 names `Accounts` as the context owning identity concerns; player identity (spec 003) will live in the same context as a sibling schema (`Player`), never sharing a table or session token with `Admin`.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
