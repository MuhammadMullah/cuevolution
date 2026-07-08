# Implementation Plan: Public Standings

**Branch**: `009-standings` | **Date**: 2026-07-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-standings/spec.md`

## Summary

Build a player-facing, real-time standings LiveView for the three categories (Individual Male, Individual Female, Team), reading Cuevo Points totals from the `Competitions` context (spec 008) and updating live via Phoenix PubSub whenever the admin records new points.

## Technical Context

**Language/Version**: Elixir 1.17+, Erlang/OTP 27+

**Primary Dependencies**: Phoenix 1.8, Phoenix LiveView, Phoenix PubSub (broadcast on points entry, subscribed by the standings LiveView)

**Storage**: PostgreSQL — no new tables; reads `cuevo_points_entries` (spec 008) via an aggregating query, exposed as `Competitions.standings_for_category/1`

**Testing**: ExUnit, `Phoenix.LiveViewTest` including a PubSub-driven live-update assertion (points entered in one process reflected in a connected LiveView test process)

**Target Platform**: Phoenix LiveView, player-facing (behind spec 003's player auth), read-only

**Performance Goals**: Standings refresh reflected to open views within a few seconds of a points entry (NFR-1.2); query itself is a straightforward grouped aggregate, fast at MVP data volumes

**Constraints**: Standings view MUST NOT be reachable from an unauthenticated session (still "no admin privileges required," per FR-002, but a player login is implied since the app has no public/anonymous browsing surface — see scope doc §6, "no public site beyond in-app standings")

**Scale/Scope**: Three category views (Individual Male, Individual Female, Team), each a single ranked table

## Constitution Check

*No formal `constitution.md` exists yet. Gates enforced from `requirements/cuevolution-requirements.md`:*

- FR-002: viewable by any registered player, no admin privilege required — **gate**: standings LiveView is mounted behind `require_player` (spec 003), never `require_admin`.
- NFR-1.2: real-time refresh window suitable for LiveView — **gate**: standings LiveView subscribes to a PubSub topic broadcast by `Competitions.record_points/2` (spec 008), rather than polling.
- NFR-7.2: context boundaries — **gate**: this feature adds a read-query function to `Competitions`, introducing no new context, since standings are a view over existing competition data.

## Project Structure

### Documentation (this feature)

```text
specs/009-standings/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```text
lib/cuevolution/
└── competitions.ex                    # Addition: standings_for_category/1 (aggregating query),
                                        #   broadcast on record_points/2 (from spec 008) to "standings" topic

lib/cuevolution_web/
└── live/
    └── player/
        └── standings_live.ex          # Category-tabbed standings view, subscribes to "standings" PubSub topic

test/cuevolution/competitions/standings_query_test.exs
test/cuevolution_web/live/player/standings_live_test.exs
```

**Structure Decision**: Single Phoenix application. No new context — `standings_for_category/1` is added to the existing `Competitions` context (spec 006/008), and the LiveView lives alongside other player-facing views under `lib/cuevolution_web/live/player/`. This feature has a hard read dependency on spec 008 (Cuevo Points data) and a hard access-control dependency on spec 003 (player auth).

## Complexity Tracking

*No constitution violations — table intentionally omitted.*
