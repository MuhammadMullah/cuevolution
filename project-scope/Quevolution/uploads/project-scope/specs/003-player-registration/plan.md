# Implementation Plan: Player Registration & Profile

**Branch**: `003-player-registration` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-player-registration/spec.md`

## Summary

Implement player self-registration (with 18+ age gate, unique username, region and venue selection, notification preference), a player login/session distinct from admin, and the region-lock rule tied to a player's first recorded match. Registration success triggers a call into the `Notifications` context (spec 002) for the confirmation event.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (registration form as a LiveView with inline/real-time validation per NFR-6.2), Ecto, bcrypt_elixir, `Cuevolution.Notifications.dispatch/3` (spec 002)

**Storage**: PostgreSQL — `players` table, `player_tokens` table (session tokens)

**Testing**: ExUnit, `Phoenix.LiveViewTest` for the registration form (validation, age gate, username uniqueness), `Cuevolution.AccountsFixtures` test factory

**Target Platform**: Phoenix LiveView, mobile-first responsive (Tailwind), low-to-mid bandwidth tolerant (NFR-8.2)

**Performance Goals**: Standard page responses under 2s even during concurrent registration bursts (NFR-1.1)

**Constraints**: Region becomes immutable once a match record exists for the player (depends on spec 008's match/result schema existing — implemented here as a query against that table, not a duplicated flag that can drift out of sync); username uniqueness enforced at the database level (unique index), not application-only

**Scale/Scope**: Single registration form, single player profile edit form, one venue-preference sub-flow (list + "Other")

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-4.1 / NFR-4.5: passwords hashed (bcrypt), all input validated/sanitized via Ecto changesets — **gate**: no raw SQL string interpolation, all form input passes through a changeset.
- NFR-6.1 / NFR-6.2: mobile-first, real-time inline validation — **gate**: registration form implemented as LiveView with `phx-change` validation, not a full-page-reload form.
- NFR-5.1 / NFR-5.3: Kenya Data Protection Act compliance, contact info used only for consented notification purposes — **gate**: no feature outside `Notifications` (spec 002) reads player email/mobile for messaging.
- NFR-2.3: data model accommodates future stages/categories without breaking existing records — **gate**: region stored as a reference to a `Region` lookup (not a free-text/enum baked into player table) so future regions can be added.

## Project Structure

### Documentation (this feature)

```text
specs/003-player-registration/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── accounts.ex                          # Context additions: register_player/1, authenticate_player/2,
│                                         #   update_notification_preference/2, region_locked?/1
├── accounts/
│   ├── player.ex                        # Ecto schema: players table
│   ├── player_token.ex                  # Ecto schema: player_tokens table
│   └── region.ex                        # Ecto schema: regions lookup table (the 8 fixed regions)

lib/cuevolution_web/
├── live/
│   └── player/
│       ├── registration_live.ex         # Multi-step or single-page registration form
│       └── profile_settings_live.ex     # Notification preference + region change (when unlocked)
├── controllers/
│   └── player_session_controller.ex     # Login/logout (mirrors admin_session_controller pattern)
└── plugs/
    └── player_auth.ex                   # fetch_current_player / require_player plugs + on_mount hook

priv/repo/migrations/
├── ..._create_regions.exs
├── ..._create_players.exs
└── ..._create_player_tokens.exs

test/cuevolution/accounts/player_registration_test.exs
test/cuevolution_web/live/player/registration_live_test.exs
```

**Structure Decision**: Single Phoenix application. `Player` and `Region` schemas live in the same `Accounts` context as `Admin` (spec 001), reflecting NFR-7.2's named context list, but with completely separate session/token tables and no shared authentication code path between player and admin.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
