# LiveView Architecture: Cuevolution.Competitions

## Recommendation

**Use LiveView**: Yes, for all 8 screens (7 admin + 1 player rewrite).

**Rationale**: Every screen is either (a) real-time multi-viewer data (StandingsLive — spec 009 FR-003/FR-004 explicitly requires live refresh without reload), (b) high-volume batch admin data entry where LiveView's server-state model avoids full-page reloads per row (FixtureEntryLive batch draws, ResultEntryLive/PointsEntryLive at volume per SC-002/NFR-6.3), or (c) admin CRUD-with-inline-edit matching the existing `VenueManagementLive` pattern (StageManagementLive, CapacityConfigLive, GroupManagementLive). None of these are static/SEO content — all sit behind `admin_required`/`player_required` auth pipelines already in `router.ex`.

## Existing Files To Rewire (not replace)

- `lib/cuevolution_web/live/admin/admin_draws_live.ex` (+ `.html.heex`) → becomes `FixtureEntryLive`. **Keep**: the `blank_row/1` batch-row model, `AdminComponents.field_search/1` combobox, `field_keyup`/`select_field`/`update_rows`/`add_row`/`remove_row` event names and the `a_suggestions`/`b_suggestions`/`venue_suggestions` per-row live-search wiring (backed by `Accounts.search_players/2`, `Teams.list_teams_filtered/1`, in-memory venue filter). **Replace**: the `"save"` handler's no-op flash with a real `Competitions.enter_fixtures/2` batch call (T080); add `round_id`/`stage_id`/`group_id` context (currently absent — rows have no round association at all); post-commit `Notifications.dispatch/3` fan-out (T082).
- `lib/cuevolution_web/live/admin/admin_results_live.ex` → becomes `ResultEntryLive` (Unplayed tab) + `PointsEntryLive` (Played tab, or a nested LiveComponent per team-frame). Keep the `tab`/`switch_tab` chrome, replace empty list with `stream/3`-backed unplayed fixtures and played-with-results.
- `lib/cuevolution_web/live/admin/admin_dashboard_live.ex` → `stat_tiles/0`'s "Fixtures this week"/"Pending results" (`—` placeholders) and `pipeline_bars: []` get real queries once `Competitions.list_fixtures/1` / `Competitions.standings_for_category/1`-style counts exist. No route/structure change.
- `lib/cuevolution_web/live/player/fixtures_live.ex` (+ `.html.heex`) → swap `upcoming_fixtures/1`/`recent_results/1` stubs for real `Competitions` queries scoped to `current_player`. Template already has correct empty-states (`PlayerComponents.empty_state`) — don't touch markup structure, just the mount-time data.
- `lib/cuevolution_web/live/player/standings_live.ex` (+ `render_standings.html.heex`) → replace `standings_rows/1` stub and hardcoded `@regions`/`@stages` module attributes with real `Accounts.list_regions()` and a real stage list, and — critically — add `connected?(socket) && subscribe to "standings"` + convert the `rows`/`all_rows` local-variable-in-`render/1` pattern to `stream/3`. This is the one T101 explicitly calls out for `Phoenix.LiveView.stream/3`.

**Visual/structural reference for all new CRUD-style LiveViews** (StageManagementLive, CapacityConfigLine, GroupManagementLive): mirror `venue_management_live.ex`'s shape exactly — region-tab `select_region` pattern, `editing_x`/`assign_form`/`validate`/`save`/`cancel_edit` event set, `load_x/1` private reload helpers called after every mutating event.

## Lifecycle Planning

```
mount/3 (disconnected + connected)
  ↓
handle_params/3 (every URL change)
  ↓
Event loop: handle_event, handle_info, handle_async
```

**Loading strategy per screen:**
- mount/3: primary resource for the screen (stages, groups, unplayed fixtures, standings snapshot)
- handle_params/3: filters only (region/stage/category tab selection via query params, pagination) — never a fresh full dataset load
- FixtureEntryLive/ResultEntryLive avoid DB queries in the disconnected mount only in the sense of Iron Law #1 being satisfied by these being auth-gated non-SEO admin routes — a straight `Competitions.list_x()` in mount is fine here (no `assign_async` needed) since there's no crawler concern and the data is small/bounded per stage.

## Page Structure — Per LiveView

### 1. `StageManagementLive` (T071) — new
- **Route**: `/admin/stages` (new, add to `router.ex` admin_authenticated live_session)
- **Assigns**: `stages` (plain assign, 4 rows max — bounded), `selected_stage`, `participations` (plain assign, filtered by stage+region+category — could be hundreds at Grassroots, borderline; start with assign + pagination via `handle_params`, revisit as `stream` if Grassroots participant counts exceed ~200 in practice per T102's perf note)
- **Events**: `select_stage`, `select_region`, `advance` (calls `Competitions.advance_to_stage/2`, T069), `advance_bulk` (selected checkboxes)
- **Key**: `advance`/`advance_bulk` must extract `%{player_id:, team_id:, region_id:, category:}` from assigns before calling the context (Iron Law #6) — never pass the LiveView socket into `advance_to_stage/2`.

### 2. `CapacityConfigLive` (T071) — new
- **Route**: `/admin/stages/capacity` (or nested tab within StageManagementLive via `push_patch` — recommend nested tab, same page, `handle_params` toggles a `:panel` assign, avoids a second full mount for what's essentially one settings form)
- **Assigns**: `configs` (plain assign, ≤6 rows: Circuit×3 categories + Finals×3 categories — bounded, never streams)
- **Events**: `edit_config`, `save_config` (calls `Competitions.capacity_config/2` update path, T070) — inline edit like `VenueManagementLive`'s `editing_venue`/`assign_form` pattern.

### 3. `GroupManagementLive` (T076) — new
- **Route**: `/admin/groups`
- **Assigns**: `stage` (Grassroots/Regional tab), `region`, `groups` (plain assign, bounded — a handful of groups per stage/region), `unassigned_participants` (plain assign, could be sizeable at Grassroots — same borderline call as above), `selected_group`
- **Events**: `select_stage`, `select_region`, `create_group`, `assign_to_group` (T074, drag-select-checkbox style), `remove_from_group`
- **Notes**: Regional grouping triggers empty-bracket creation (T075) — surface via flash, not a separate screen for MVP.

### 4. `FixtureEntryLive` (T085) — rewires `AdminDrawsLive`
- **Route**: `/admin/draws` (existing route, same module rename or alias)
- **Assigns**: `round` (selected round, plain assign), `rows` (in-progress batch-entry scratchpad, plain assign — bounded to a single round's worth, ~8-16 per SC-002), `entered_fixtures` **stream** (already-saved fixtures for the round — this list is uncapped across a season, MUST be `stream/3`, not the scratchpad `rows`)
- **Events** (kept from existing): `add_row`, `remove_row`, `update_rows`, `field_keyup`, `select_field`, `noop`. **New**: `select_round`, `save` (real — calls `Competitions.enter_fixtures/2`, per-row `Ecto.Multi`, T080; partial-success UI shows which rows failed with specific errors per FR-009/SC-005).
- **Data flow out**: on successful `save`, for each created fixture → post-commit (NOT inside the `Ecto.Multi` transaction — T082 is explicit about this) call `Notifications.dispatch(participant_a, :fixture_assignment, %{opponent_name: b.name, venue: venue.name, date:, time:})` and the mirrored call for participant B. Team-category fixtures dispatch to each roster member (or captain only — `Notifications.dispatch/3` only accepts a `%Player{}`, so team fixtures fan out per-player, following the existing `Teams.dispatch_team_assignment/2` pattern in `lib/cuevolution/teams.ex`).
- **Edit path** (T083): same LiveView, `edit_fixture` event, locked (inputs disabled) once `fixture.result_id` is set — checked via `Competitions.update_fixture/2` returning an explicit `{:error, :locked}` rather than allowing the UI to silently no-op.

### 5. `ResultEntryLive` (T098) — rewires `AdminResultsLive`'s "Unplayed" tab
- **Route**: `/admin/results` (existing route)
- **Assigns**: `tab` (kept), `unplayed_fixtures` **stream** (uncapped across a season — MUST stream), `selected_fixture`, `result_form`
- **Events**: `switch_tab` (kept), `select_fixture`, `validate_result`, `record_result` (T090, calls `Competitions.record_result/2`), `correct_result` (T091, opens correction form pre-filled with `prior_value`, surfaces the downstream-advancement warning per US4 scenario 3 as a flash/banner, not silently)
- **Team-category**: nested frame entry — either a `LiveComponent` (`MatchFrameFormComponent`) since it has real internal form state (frame-by-frame winner selection) distinct from the parent's fixture-selection state, or inline `<.form>` with a frame fieldset. LiveComponent justified here per the decision tree (internal state + event handling + encapsulates real application logic, not just DOM).

### 6. `PointsEntryLive` (T098) — "Played" tab or same module as ResultEntryLive
- **Route**: `/admin/results` (tab-switched, same as above — recommend collapsing into `ResultEntryLive` with `tab` assign rather than a separate route, matching existing `AdminResultsLive` chrome, since both operate on the same played-fixture stream)
- **Assigns**: `played_fixtures` **stream**, `points_form` per participant/frame
- **Events**: `record_points` (T095, `Competitions.record_points/2`), `correct_points` (T095, `Competitions.correct_points/2` — correction affordance is a hard requirement per T098's own description)
- **Data flow out**: `record_points`/`correct_points` → `Competitions.points_total/1` recompute (live SUM, never cached, per T096) → `Phoenix.PubSub.broadcast(Cuevolution.PubSub, "standings", {:points_updated, participant_id})` (T100) → picked up by `StandingsLive`.

### 7. `StandingsLive` (T101) — rewires player-facing `standings_live.ex`
- **Route**: `/standings` (existing player route, unchanged)
- **Assigns**: `tab` (male/female/team, kept), `region_filter`/`stage_filter` (kept), `standings` **stream** (uncapped — T101 explicitly names `Phoenix.LiveView.stream/3`)
- **mount/3**: `if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")` (Iron Law #3) before the initial `Competitions.standings_for_category/1` stream populate.
- **handle_info/3**: `{:points_updated, _participant_id}` → re-run `standings_for_category/1` for the current tab, `stream(socket, :standings, rows, reset: true)` (full reset is fine here — the whole point is a re-ranked list, not an incremental diff).
- **Filter events**: `switch_tab`/`filter`/`clear_filters` (kept) — these trigger a fresh stream repopulate (`reset: true`), not a subscription change (still same `"standings"` topic regardless of tab).

## State Management (StandingsLive example)

```elixir
%{
  page_title: "Standings",
  tab: "male",
  region_filter: "All",
  stage_filter: "All",
  tabs: [...],       # bounded, plain assign
  regions: [...],    # bounded, plain assign — from Accounts.list_regions()
  stages: [...],     # bounded, plain assign
  streams: %{standings: [...]}  # uncapped — stream/3
}
```

## Async Operations

| Pattern | Use When |
|---------|----------|
| Plain mount query | Bounded admin lists (stages, capacity configs, groups) — no `assign_async` needed, auth-gated non-SEO |
| `stream/3` | entered-fixtures list, unplayed/played fixtures list, standings — all uncapped over a season |
| Post-commit side effect (not `assign_async`) | `Notifications.dispatch/3` after `enter_fixtures/2` commits — explicitly required to run *outside* the DB transaction (T082) |

## Events Summary

| Event | Trigger | Handler → Context |
|-------|---------|-------------------|
| "save" (FixtureEntryLive) | batch draw submit | `Competitions.enter_fixtures/2` → post-commit `Notifications.dispatch/3` × 2 per fixture |
| "record_result" | admin enters winner/score | `Competitions.record_result/2` |
| "correct_result" | admin fixes mis-entry | `Competitions.correct_result/2` → `Accounts.log_admin_action/4` |
| "record_points" | admin enters Cuevo Points | `Competitions.record_points/2` → PubSub broadcast "standings" |
| "correct_points" | admin fixes points | `Competitions.correct_points/2` → PubSub broadcast "standings" |
| "advance" | admin advances stage | `Competitions.advance_to_stage/2` (atomic capacity check, T069) |

## Navigation Architecture

- Tab switches within a LiveView (StandingsLive tabs, AdminResultsLive tabs, region tabs) → local `assign` + optional `push_patch` if reflected in URL query params (recommended for shareable/bookmarkable filtered views).
- FixtureEntryLive round selection → `push_patch` to `/admin/draws?round_id=X` (handle_params-driven, satisfies Iron Law #5: pagination/round-selection in `handle_params`, not remount).
- Cross-LiveView (e.g., dashboard "Pending results" tile → ResultEntryLive) → `push_navigate` (`<.link navigate={...}>`), different live_session boundary not crossed (still `:admin_authenticated`).

## PubSub Topics

| Topic | Publisher | Subscribers |
|-------|-----------|-------------|
| `"standings"` | `Competitions.record_points/2`, `Competitions.correct_points/2` (T100) | `StandingsLive` (player-facing) |

No other new PubSub topics are required by the tasks/specs read — draws notifications go through `Notifications.dispatch/3` (Oban-backed email/SMS), not PubSub; there's no live "opponent just got notified" UI to update.

## Streams vs Assigns — Explicit Call

| List | Decision | Why |
|------|----------|-----|
| `standings` (StandingsLive) | **stream** | Explicitly named in T101; uncapped across whole league |
| entered fixtures (FixtureEntryLive) | **stream** | Grows across a season, no natural cap |
| unplayed/played fixtures (ResultEntryLive) | **stream** | Same — season-long accumulation |
| in-progress batch draw rows (FixtureEntryLive scratchpad) | **assign** | Bounded to one round's entry session (~8-16 rows), never persisted as a stream item until saved |
| stages (StageManagementLive) | **assign** | Fixed 4 rows |
| capacity configs (CapacityConfigLive) | **assign** | Fixed ≤6 rows |
| groups (GroupManagementLive) | **assign** | Small, bounded per stage/region |
| group/stage participants list (StageManagementLive, GroupManagementLive "unassigned" list) | **assign, but flag for T102 perf review** | Could reach hundreds at Grassroots — start as assign+filter, promote to stream if `EXPLAIN ANALYZE` (T102) or real usage shows it's costly |

## Data Flow (End-to-End)

```
FixtureEntryLive "save"
  → Competitions.enter_fixtures/2 (Ecto.Multi, per-row)
  → [commit] → Notifications.dispatch(player_a, :fixture_assignment, %{opponent_name:, venue:, date:, time:})
             → Notifications.dispatch(player_b, :fixture_assignment, %{...})
  → player FixturesLive (next mount/visit) shows the new fixture in `upcoming_fixtures/1`

ResultEntryLive "record_result"
  → Competitions.record_result/2
  → fixture.result_id set → FixtureEntryLive's edit path now locks that fixture

PointsEntryLive "record_points" / "correct_points"
  → Competitions.record_points/2 / correct_points/2
  → Phoenix.PubSub.broadcast(Cuevolution.PubSub, "standings", {:points_updated, participant_id})
  → StandingsLive.handle_info/2 → re-stream standings_for_category/1 (reset: true)
```

## If NOT LiveView

N/A — all 8 screens satisfy at least one strong LiveView criterion (real-time PubSub-driven updates, high-volume batch entry, or inline-CRUD matching the existing `VenueManagementLive` house style). No dead-view alternative was considered viable given the existing admin app is entirely LiveView-based already.
