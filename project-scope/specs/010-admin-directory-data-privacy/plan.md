# Implementation Plan: Admin Directory & Data Privacy

**Branch**: `010-admin-directory-data-privacy` | **Date**: 2026-07-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-admin-directory-data-privacy/spec.md`

## Summary

Add an admin-facing, filterable directory over `Accounts.Player` and `Teams.Team`, and a `Accounts.anonymize_player/2` action that scrubs PII in place while preserving every foreign-key reference from `Competitions` (stage participation, match results, points entries). Closes the two requirements (FR-9.3, NFR-5.2) identified in the system design review as cited but never implemented.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView (filterable directory table, using `Phoenix.LiveView.stream` since player/team counts are uncapped at Grassroots — see design system §4.3), Ecto

**Storage**: PostgreSQL — no new tables; adds `anonymized_at` (timestamptz, nullable) to `players`, plus a placeholder-name strategy (e.g., `display_name` computed as `"Former Player ##{id}"` when `anonymized_at` is set)

**Testing**: ExUnit, `Phoenix.LiveViewTest` for directory filtering, a dedicated test asserting historical `match_results`/`cuevo_points_entries` remain queryable and correctly attributed after anonymization

**Target Platform**: Phoenix LiveView, admin-only (behind spec 001's RBAC gate)

**Performance Goals**: Directory filter queries use indexed columns (`region_id`, `stage_id`, `category`) — sub-second at MVP data volumes

**Constraints**: Anonymization must be irreversible and must not cascade-delete any row in `Competitions` — enforced by only ever `UPDATE`ing the `players` row's PII columns, never touching child tables

**Scale/Scope**: One directory view (players), one directory view (teams), one anonymize action with a confirmation step

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- NFR-5.1/NFR-5.2: Kenya DPA compliance, anonymization without breaking historical records — **gate**: anonymize action is a pure `UPDATE` on `players` PII columns; a test explicitly re-reads `match_results`/`cuevo_points_entries` post-anonymization to prove no cascade occurred.
- NFR-4.2: admin-only — **gate**: directory and anonymize action both mounted under `require_admin`.
- NFR-9.1: admin actions logged — **gate**: anonymize action calls the spec 001 admin-action-log function.
- NFR-7.2: context boundaries — **gate**: directory read functions and `anonymize_player/2` live in `Accounts` (players) and `Teams` (teams), not a new context, since they operate on those contexts' own data.

## Project Structure

### Documentation (this feature)

```text
specs/010-admin-directory-data-privacy/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
├── accounts.ex                        # Additions: list_players_filtered/1, anonymize_player/2
└── accounts/
    └── player.ex                      # Addition: anonymized_at field, display_name/1 helper

lib/cuevolution/
└── teams.ex                           # Addition: list_teams_filtered/1

lib/cuevolution_web/
└── live/
    └── admin/
        ├── player_directory_live.ex   # Filterable player list (stream-based)
        ├── team_directory_live.ex     # Filterable team list (stream-based)
        └── player_detail_live.ex      # Full profile view + "Anonymize" action with confirmation

priv/repo/migrations/
└── ..._add_anonymized_at_to_players.exs

test/cuevolution/accounts/anonymize_player_test.exs
test/cuevolution_web/live/admin/player_directory_live_test.exs
```

**Structure Decision**: Single Phoenix application. No new context — directory queries and the anonymize action extend `Accounts` and `Teams` directly, since FR-9.3/NFR-5.2 are operations *on* those contexts' existing data, not a new domain concept.

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
