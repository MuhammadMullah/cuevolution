# Cuevolution — System Design Review

> **Resolution status (2026-07-08): all findings below have been applied to the specs and design system.** See the [Resolution Log](#resolution-log) at the end of this document for exactly what changed and where. The findings themselves are left intact below as the historical record of what was found and why — the resolution log is the pointer to the fix.

**Reviewed**: 2026-07-07
**Scope**: `requirements/`, all 9 specs in `specs/001`–`009`, `design/design-system.md` + `tokens.css`
**Explicitly out of scope for this review** (confirmed intentional MVP exclusions, not flagged as gaps below): rate limiting / login throttling, multi-admin or regional-admin roles, payments, automatic points formulas, mobile native apps.

This is a cross-cutting review — it does not re-litigate individual spec decisions already marked `[NEEDS CLARIFICATION]` or `Assumptions` inline (those are doing their job); it looks for what's missing *between* specs, what's ambiguous in a way that blocks implementation, and what will silently corrupt data or disputes once the system is live with real matches and money-adjacent stakes (league standing, qualification).

Findings are grouped by severity. Each has a concrete recommendation, not just a question.

---

## 1. Critical — will cause disputes or incorrect competition outcomes

### 1.1 Two requirements were traced but never actually implemented in any spec

- **FR-9.3** ("admin shall view all registered players and teams filtered by region, category, and stage") is cited in [`001-admin-authentication/spec.md:11`](../specs/001-admin-authentication/spec.md) traceability header, but none of FR-001–FR-007 in that spec (lines 72–78) implement it, and no other spec owns an admin directory/browse view. **This requirement currently has no home.**
- **NFR-5.2** ("admin shall be able to remove or anonymize a player's personal data upon a valid deletion request, without breaking historical match/points records") is cited in [`003-player-registration/spec.md:11`](../specs/003-player-registration/spec.md), but none of FR-001–FR-012 (lines 75–86) implement it. **Deletion/anonymization has no home either.**

**Recommendation**: Add a 10th spec (`010-admin-directory-and-data-privacy`, or split into two if you want them independently prioritized) covering:
- Admin: searchable/filterable list of all players and teams by region, category, current stage.
- Admin: a "deactivate/anonymize player" action that scrubs PII (name, email, mobile, profile picture, location) while preserving the player's row as a stub so `match_results`, `cuevo_points_entries`, and historical standings keep a valid foreign key.

This is the single most important gap in the whole spec set — it's a legal-compliance item (Kenya Data Protection Act, 2019, cited directly in NFR-5.1) with zero implementation coverage.

### 1.2 No tiebreaker rule for Grassroots/Regional group standings

[`008-match-results-points/spec.md:40`](../specs/008-match-results-points/spec.md) says participants are "ranked by their group results (e.g., match wins)" — this is the ranking that decides who actually advances to Regional, and who makes the top-8 knockout cut at Regional. There is no defined tiebreaker (head-to-head result, frame/game differential, total frames won, etc.).

This is materially different from the tiebreaker gap already flagged in [`009-standings/spec.md:47`](../specs/009-standings/spec.md) — that one only affects *display order* on a leaderboard. This one decides **who is eliminated from the tournament**. A wrong or absent rule here is the single most likely source of a real dispute once Grassroots groups start reporting results.

**Recommendation**: Before writing `tasks.md` for spec 008, get an explicit ranking formula from the league (typical pool league convention: match wins → head-to-head → frame/rack differential → coin toss/admin discretion as last resort). Encode it as an ordered list of tiebreaker criteria in the `StandingsCalculator` module named in [`008-match-results-points/plan.md`](../specs/008-match-results-points/plan.md), not as an ad hoc `ORDER BY`.

### 1.3 "Top 8 per group" boundary ties are undefined

Directly related to 1.2: if participants ranked 8th and 9th are tied, the system cannot deterministically produce "the top 8" without the same tiebreaker rule from 1.2. [`008-match-results-points/spec.md:54`](../specs/008-match-results-points/spec.md) only handles the "fewer than 8 in the group" edge case, not the "tied at the boundary" one. Same recommendation as 1.2 — one shared tiebreaker rule resolves both.

### 1.4 Region-lock trigger is ambiguous: fixture creation vs. recorded result

[`003-player-registration/spec.md:82`](../specs/003-player-registration/spec.md) (FR-008) locks a player's region "once a match record exists," and the scope doc says "before their first recorded match." But a *fixture* (draw entry, spec 007) is created before a match is played, and a *result* (spec 008) is recorded only after. These are two different events with two different tables. As written, an implementer could reasonably lock the region the moment a fixture is drawn (before the player has even played), which would be a meaningfully stricter and more disruptive rule than locking on result entry.

**Recommendation**: Explicitly define the lock trigger as **"a `Match Result` row exists referencing this player"** (spec 008's entity), not fixture/draw creation. Update FR-008 in spec 003 to reference spec 008's `Match Result` entity by name instead of the ambiguous phrase "match record."

### 1.5 No roster-freeze rule for teams once competition begins

Spec 003 locks an individual player's region after their first match specifically "to preserve the integrity of regional standings and pipelines" ([`003-player-registration/spec.md:49`](../specs/003-player-registration/spec.md)). No equivalent protection exists for **team rosters** in [`005-team-management/spec.md`](../specs/005-team-management/spec.md) — a captain can add/remove players at any time, including after the team has advanced through Grassroots, Regional, or into Circuit. As written, a team could qualify with one roster and field an entirely different set of players by Finals.

**Recommendation**: Decide explicitly whether this is acceptable (many amateur leagues do allow squad rotation) or whether roster changes should freeze once the team's first team-match result exists, mirroring 1.4's player rule. Either way, this should be a stated decision, not a silent gap — right now it reads as an oversight rather than a choice.

### 1.6 Team-vs-team match result format is undefined

[`008-match-results-points/spec.md:96`](../specs/008-match-results-points/spec.md) models `Match Result` as "fixture reference, winner reference, score (if applicable)" — i.e., **one winner per fixture**. Competitive pool team formats commonly resolve a team tie as a race across multiple individual frames/legs between different pairs of players from each roster (e.g., best-of-9 individual frames). If that's how Cuevolution's Team category actually works, a single winner/loser per fixture cannot capture per-player Cuevo Points within a team tie, and the data model in spec 008 needs a `frame`/`leg` sub-entity under `Fixture`, not just a flat result.

**Recommendation**: This needs a direct answer from whoever owns the competition rules before spec 008's schema is built: is a Team fixture (a) one aggregate result for the whole team, or (b) a set of individual frames each contributing to the team score? This changes the schema, not just a validation rule, so it's worth resolving before `tasks.md` rather than during implementation.

### 1.7 Gender field has no defined mapping to the two individual categories

FR-1.1 collects "gender" as an open registration field, but the competition model has exactly two individual categories: Individual Male and Individual Female ([`cuevolution-scope.md:30-31`](../requirements/cuevolution-scope.md)). No spec states how a player's `gender` value maps to their competition `category`, or what happens if they don't coincide (e.g., a value outside a strict male/female binary). Given NFR-5.1 explicitly invokes the Kenya Data Protection Act (lawful basis, data minimization) for this exact field, this is a data-governance question as much as a technical one, not just a form-validation detail.

**Recommendation**: Get an explicit decision on the accepted values for `gender`/`category` and whether they're the same field or two distinct fields (a self-described gender vs. a competition-category assignment) before building spec 003's schema.

---

## 2. High — concurrency and data-integrity gaps that will surface as subtle bugs

### 2.1 Stage-capacity check is a classic TOCTOU race

[`006-qualification-pipeline/plan.md`](../specs/006-qualification-pipeline/plan.md) describes capacity checks as "a simple count-and-compare query." Two concurrent "advance to Circuit" actions (plausible if the admin has two browser tabs open — a scenario spec 001 itself flags as unresolved in [`001-admin-authentication/spec.md:66`](../specs/001-admin-authentication/spec.md)) could both pass the count check before either write commits, exceeding the configured cap. Spec 005 already solved the equivalent problem correctly (`Ecto.Multi` + a DB-level unique constraint for "one team per player" — see [`005-team-management/plan.md`](../specs/005-team-management/plan.md)); spec 006's advancement action needs the same treatment: a transaction with a row lock (`SELECT ... FOR UPDATE` on the capacity config row) or an equivalent DB-enforced guard, not an application-level count-then-insert.

### 2.2 Notification retry is not proven idempotent

Oban (per [`002-notifications-infrastructure/plan.md`](../specs/002-notifications-infrastructure/plan.md)) retries a failed job by re-running it from the top. If the actual send (email/SMS provider call) succeeds but the process crashes before the `notifications` row is marked `sent`, the retry will resend the message — a player could receive the same fixture notification twice. Worth an explicit design note: either make the provider call itself idempotent (many providers support an idempotency/client-reference key), or persist "send attempted" state *before* the provider call so a crash mid-send is distinguishable from a not-yet-attempted send.

### 2.3 No duplicate-fixture guard within a single round

[`007-draws-management/spec.md:64`](../specs/007-draws-management/spec.md) correctly notes that the *same two participants* meeting again in a *later* round is legitimate (group stage vs. knockout) and shouldn't be flagged as a duplicate. But nothing prevents the same pairing being entered **twice within the same round** — a plausible double-submit or duplicate CSV row. Recommend a uniqueness constraint scoped to `(round_id, participant_a, participant_b)` rather than global, so legitimate rematches across rounds remain unaffected.

### 2.4 Batch/CSV upload partial-failure behavior is undefined

Both [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) (fixture batch entry) and the Assumptions section acknowledge batch entry is expected but don't say what happens when row 12 of a 20-row batch is invalid: does the whole batch reject, or do rows 1–11 and 13–20 commit while row 12 is reported as an error? Given NFR-6.3's goal of minimizing manual admin steps for volume entry, an all-or-nothing rejection on one bad row would be a poor experience for someone entering a full round. Recommend: partial commit with a per-row error report, and make this explicit in spec 007 before implementation.

### 2.5 Admin correction workflow for results/points is deferred, but is unlikely to stay optional

[`008-match-results-points/spec.md:76`](../specs/008-match-results-points/spec.md) already flags this as `[NEEDS CLARIFICATION]` and the Assumptions section defers it to "a future iteration if it proves necessary." Worth reconsidering before committing to that: mis-entered results/points during a live, multi-round tournament are closer to a certainty than an edge case — an admin fat-fingering a score during in-person data entry at a venue is routine, not exceptional. Recommend pulling a minimal "correct an entry" action into the MVP scope for this spec rather than treating it as deferred, since the workaround (delete-and-reinsert at the DB level) is exactly the kind of manual, unaudited operation the audit-log requirement (NFR-9.1) exists to prevent.

### 2.6 Admin action log doesn't capture before/after values

[`001-admin-authentication/spec.md:84`](../specs/001-admin-authentication/spec.md) defines `Admin Action Log` as capturing "the action type... the affected entity, and a timestamp" — explicitly *not* a field-level change history (Assumptions, line 99). For a dispute like "the standings show 15 points but I only entered 10," a log that says "points entered for Player X, match Y, by Admin, at time Z" without the actual value entered doesn't resolve anything. Recommend the log (or the `cuevo_points_entries`/`match_results` rows themselves, which already have `recorded_by`/timestamp per spec 008) be sufficient to reconstruct "what value was submitted," even if a full diff-style audit trail is out of scope.

---

## 3. Medium — real gaps, lower blast radius

- **Fixture notification content must not leak the opponent's contact info.** Neither [`002-notifications-infrastructure/spec.md`](../specs/002-notifications-infrastructure/spec.md) nor [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) explicitly states that a fixture notification should contain the opponent's *name* only, not their email/phone. Worth an explicit constraint given NFR-4.4/NFR-5.3.
- **Mobile number format/normalization is unspecified.** FR-1.1 collects a mobile number but no spec states validation/normalization (e.g., E.164, Kenyan `+254` prefix handling) — needed before the SMS adapter (spec 002) can reliably dispatch.
- **Timezone convention is implicit.** Fixture date/time (spec 007) should explicitly state "stored UTC, displayed in East Africa Time (UTC+3)" rather than leaving it to implementation-time guesswork.
- **Fixture entry trusts the admin completely** ([`007-draws-management/spec.md:61`](../specs/007-draws-management/spec.md) edge case) — reasonable as a conscious MVP tradeoff, but a cheap guard (reject a fixture if the two participants aren't the same category, or aren't both marked eligible per spec 005/006) would catch fat-finger errors before they corrupt a group's standings, for very little implementation cost. Worth reconsidering as an actual FR rather than a fully-trusted no-check policy.
- **Single admin account is a single point of failure.** Distinct from "no multi-admin roles" (an intentional scope decision) — there is currently no break-glass/recovery path if the one admin's credential is lost mid-tournament. Worth a documented operational mitigation (e.g., a securely stored recovery mechanism) even though it doesn't need a second role in the UI.
- **Deployment/ops-level NFRs have no owner.** NFR-3.1 (availability during tournament windows), NFR-3.3 (Postgres backups/PITR), NFR-4.3 (TLS/HTTPS), and NFR-9.2 (general app health/error monitoring beyond notification failures) aren't covered by any feature spec — which is *appropriate*, since these are deployment/infra concerns, not product features. Flagging only so they're captured in a deployment runbook (the `elixir-phoenix:deploy` skill/plan covers this ground) rather than falling through entirely.

---

## 4. Design System Review

### 4.1 Confirmed contrast failure: `ink-400` fails WCAG AA for text use

I recomputed the contrast ratio for `--color-ink-400` (`#9E9EA7`) against white/`ink-25`: **~2.66:1**, well below the 4.5:1 AA threshold for normal text (and below the 3:1 threshold even for large text/UI components). As documented in [`design/design-system.md`](../design/design-system.md) §3.1, this token is assigned to "placeholder text, disabled text, icon default" — real usages that need to pass contrast. `ink-500` (`#6E6D7A`), by contrast, computes to **~5.08:1** and safely passes AA.

**Recommendation**: Restrict `ink-400` to decorative/large-scale use only (e.g., large icons, dividers) and move placeholder/disabled *text* usage to `ink-500` or darker. I can patch `design-system.md` directly if you want this fixed now rather than just flagged.

### 4.2 Missing component states

The component section (§6) defines resting/hover/focus states but not: **loading/skeleton** (standings table while data loads), **empty states** (no venues yet in a region, empty team roster, no notifications logged), and **disabled** button/input styling. Given LiveView's async patterns are core to this stack, at least a skeleton/loading convention for the standings and admin tables should be defined before those LiveViews are built.

### 4.3 No LiveView-scale guidance for potentially large tables

Standings (spec 009) and admin player/team directories (§1.1's recommended new spec) can grow into the hundreds of rows (Grassroots is uncapped). The design system doesn't mention `Phoenix.LiveView.stream` — the standard mitigation for socket-assign memory bloat on long lists in LiveView. Worth adding a line to §6.5 (Tables) recommending streams for any table with an unbounded/uncapped row count (Grassroots standings, admin directory), since this is a common and easy-to-miss LiveView performance pitfall.

### 4.4 No image-handling guidance for profile pictures despite NFR-8.2

The design system doesn't address responsive image sizing/compression for uploaded profile pictures, despite NFR-8.2 ("low-to-mid bandwidth conditions"). Worth a short addition: max upload dimensions, server-side resize/compress on upload, and lazy-loading avatar images in list views (standings, team roster).

### 4.5 No stated position on localization

Target audience is Kenya; the design system (and every spec) is written English-only with no mention of Swahili. This is likely the right MVP call, but it's currently an implicit assumption rather than a stated one anywhere in `design/` or `requirements/`.

---

## 5. Summary — recommended next actions before writing `tasks.md`

In priority order:

1. Resolve **§1.1** — decide where FR-9.3 (admin directory) and NFR-5.2 (deletion/anonymization) live; I'd recommend a new `010` spec.
2. Get a concrete **tiebreaker rule** (§1.2/1.3) from whoever owns competition rules — this blocks spec 008's `StandingsCalculator` design.
3. Resolve **§1.4** (region-lock trigger) and **§1.6** (team match format) — both are schema-defining decisions, cheaper to fix now than after tables exist.
4. Decide **§1.5** (roster freeze) and **§2.5** (results/points correction) — both are "should this be in MVP or explicitly deferred" product calls, not technical ones.
5. Carry **§2.1–2.4** and **§4.1** forward as implementation constraints when `tasks.md` is generated for specs 002, 006, 007, and the design system respectively — these don't need a product decision, just correct implementation.

I can update the affected spec files directly once you've made the calls in items 1–4 above, and/or patch the `ink-400` contrast issue in the design system now if you'd like — say the word.

---

## Resolution Log

Applied 2026-07-08. Where a finding required a genuine business-rules decision that only the league can make with certainty (tiebreakers, team match format, roster freeze, gender/category mapping), a concrete best-effort default was chosen and documented in place, flagged for league confirmation rather than left blocking. Rate limiting and multi-admin roles were reconfirmed as intentional exclusions and were not touched.

| § | Finding | Resolution |
|---|---|---|
| 1.1 | FR-9.3 (admin directory) and NFR-5.2 (deletion/anonymization) had no home | New spec [`010-admin-directory-data-privacy`](../specs/010-admin-directory-data-privacy/spec.md) (+ plan.md) added, covering both |
| 1.2 / 1.3 | No tiebreaker for group standings or top-8 boundary ties | [`008-match-results-points/spec.md`](../specs/008-match-results-points/spec.md) FR-013: explicit 5-step cascade (match wins → head-to-head → frame differential → total frames won → admin discretion) — flagged for league confirmation |
| 1.4 | Region-lock trigger ambiguous (fixture vs. result) | [`003-player-registration/spec.md`](../specs/003-player-registration/spec.md) FR-008 now explicitly keyed to spec 008's `Match Result`, not spec 007's `Fixture` |
| 1.5 | No team roster freeze | [`005-team-management/spec.md`](../specs/005-team-management/spec.md) FR-008/FR-009: roster locks after the team's first `Match Result`, with a logged admin override — flagged as reversible if the league prefers open squad rotation |
| 1.6 | Team-vs-team match format undefined | [`008-match-results-points/spec.md`](../specs/008-match-results-points/spec.md) FR-011/FR-012 + new `Match Frame` entity: individual-frames-within-a-tie default — flagged prominently for league confirmation since it's schema-defining |
| 1.7 | Gender-to-category mapping undefined | [`003-player-registration/spec.md`](../specs/003-player-registration/spec.md) FR-014: `gender` collected as a controlled Male/Female choice used directly as competition category — flagged for confirmation given its data-governance sensitivity |
| 2.1 | Stage-capacity check was a TOCTOU race | [`006-qualification-pipeline/plan.md`](../specs/006-qualification-pipeline/plan.md): atomic conditional `UPDATE ... WHERE current_count < capacity_limit` inside the advancement transaction, replacing count-then-insert |
| 2.2 | Notification retries not proven idempotent | [`002-notifications-infrastructure/spec.md`](../specs/002-notifications-infrastructure/spec.md) FR-009 + plan.md: unique `idempotency_key`, status moved to `sending` before the provider call |
| 2.3 | No duplicate-fixture guard within a round | [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) FR-007 + plan.md: unique index on `(round_id, unordered participant pair)` |
| 2.4 | Batch upload partial-failure semantics undefined | [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) FR-009: per-row commit/report, not all-or-nothing |
| 2.5 | Results/points correction deferred | [`008-match-results-points/spec.md`](../specs/008-match-results-points/spec.md) new User Story 4 (P1), FR-009/FR-010: pulled into MVP scope, not deferred |
| 2.6 | Admin action log lacked before/after values | [`001-admin-authentication/spec.md`](../specs/001-admin-authentication/spec.md) FR-005 + entity definition: `prior_value`/`new_value` captured for correction-type actions |
| §3 | Opponent contact-info leakage risk | [`002-notifications-infrastructure/spec.md`](../specs/002-notifications-infrastructure/spec.md) FR-010 and [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) FR-010: payload allowlist enforced at the `dispatch/3` boundary, not left to caller discipline |
| §3 | Mobile number format unspecified | [`003-player-registration/spec.md`](../specs/003-player-registration/spec.md) FR-013: E.164 normalization, Kenya `+254` default |
| §3 | Timezone convention implicit | [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) FR-008: stored UTC, displayed EAT |
| §3 | Fixture entry fully trusted the admin | [`007-draws-management/spec.md`](../specs/007-draws-management/spec.md) FR-006: category/stage cross-check added as a cheap guard |
| §3 | Single admin, no break-glass path | [`001-admin-authentication/spec.md`](../specs/001-admin-authentication/spec.md) Edge Cases: documented as an operational (not in-app) mitigation |
| §3 | Deployment-level NFRs (TLS, backups, monitoring) unowned | Confirmed as appropriately out of feature-spec scope; left for a deployment runbook rather than forced into a product spec |
| 4.1 | `ink-400` fails WCAG AA for text on light backgrounds | [`design/design-system.md`](../design/design-system.md) §2.2 + `tokens.css`: usage restricted to decorative/large-scale on light backgrounds (confirmed safe as text on dark `ink-950`/`ink-900`); placeholder/disabled text moved to `ink-500` |
| 4.2 | Missing loading/empty/disabled states | [`design/design-system.md`](../design/design-system.md) new §6.9, plus disabled-state utilities added to §6.1/§6.2 |
| 4.3 | No LiveView streams guidance for large tables | [`design/design-system.md`](../design/design-system.md) §6.5: streams required for uncapped tables (standings, admin directory) |
| 4.4 | No image/bandwidth guidance | [`design/design-system.md`](../design/design-system.md) new §10 (Media & Bandwidth) |
| 4.5 | No stated localization position | [`design/design-system.md`](../design/design-system.md) new §11: English-only for MVP, `Gettext`-ready |

**Still open, by design** — these need a human answer, not another spec edit, before the relevant `tasks.md` is written:
- Confirm the FR-013 tiebreaker cascade and the FR-011/FR-012 team-frame match format against Cuevolution's actual competition rules.
- Confirm the FR-014 gender/category default (controlled Male/Female mapped directly to competition category) reflects how the league wants to handle this field.
- Confirm whether the FR-008/FR-009 team roster freeze (spec 005) matches the league's intent, or whether open squad rotation is actually preferred.
