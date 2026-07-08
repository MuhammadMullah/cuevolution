# Implementation Plan: Venue Management

**Branch**: `004-venue-management` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-venue-management/spec.md`

## Summary

Build a `Venues` context with admin-facing CRUD (create/edit/deactivate) for venues scoped to one of the 8 regions, a read API for region-filtered venue lists consumed by player registration (spec 003), and storage/visibility for custom "Other" venue entries captured during registration.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (admin venue management screen with live table + form), Ecto

**Storage**: PostgreSQL — `venues` table (region_id FK, active boolean), `regions` table (shared lookup, owned by spec 003's migration but referenced here)

**Testing**: ExUnit, `Phoenix.LiveViewTest` for the admin CRUD LiveView

**Target Platform**: Phoenix LiveView, admin-only area (behind spec 001's RBAC gate)

**Performance Goals**: Venue list queries scoped by region use an indexed foreign key lookup; trivial data volume (tens of venues per region) so no special caching needed for MVP

**Constraints**: Deleting a venue must not orphan existing player records that reference it — implemented as an `active` boolean flag rather than a hard delete (FR-004)

**Scale/Scope**: 8 regions × a handful of venues each; single admin CRUD screen

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-4.2: venue management is admin-only — **gate**: LiveView mounted under the `require_admin` `on_mount` hook from spec 001.
- NFR-2.3: data model accommodates growth without breaking existing records — **gate**: soft-delete (`active` flag) instead of hard delete.
- NFR-7.2: context boundaries — **gate**: `Venues` is its own context per the NFR-7.2 list; `Accounts`/player registration only calls `Venues.list_active_for_region/1`, never queries the `venues` table directly.

## Project Structure

### Documentation (this feature)

```text
specs/004-venue-management/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── venues.ex                     # Context: list_active_for_region/1, create_venue/1,
│                                  #   update_venue/2, deactivate_venue/1
└── venues/
    └── venue.ex                  # Ecto schema: venues table

lib/cuevolution_web/
└── live/
    └── admin/
        └── venue_management_live.ex   # Admin CRUD screen (list + form + deactivate action)

priv/repo/migrations/
└── ..._create_venues.exs

test/cuevolution/venues_test.exs
test/cuevolution_web/live/admin/venue_management_live_test.exs
```

**Structure Decision**: Single Phoenix application. `Venues` is a standalone context; `regions` table is treated as a shared lookup owned by the `Accounts` migration set (spec 003) since regions are a fixed, cross-cutting concept, while `venues` belongs entirely to this feature.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
