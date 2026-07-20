# Prompt for Claude Design (claude.ai/design): sync design source with shipped Competitions implementation

Paste everything below into a Claude Design session. The current design source of truth is `project-scope/Quevolution/*.dc.html` (specifically `Cuevolution Admin.dc.html` and `Cuevolution Player App.dc.html`) plus `project-scope/Quevolution/uploads/design-system.md`/`tokens.css` — attach or paste those in as the starting point, not a blank canvas, so the new screens inherit the existing components/tokens instead of reinventing them.

---

## Context

Cuevolution's qualification-pipeline implementation (Elixir/Phoenix) shipped several screens and a business-rule correction that the current design files never covered. The functional specs (`project-scope/specs/006-qualification-pipeline`, `007-draws-management`, `008-match-results-points`, `009-standings`, `010-admin-directory-data-privacy`) are the up-to-date source of truth for *behavior* — read them for exact wording. This prompt tells you *which screens* need new or updated designs and the *shape* of each, so the design file catches up to what's real.

**The core rule change**: knockouts do NOT happen at Grassroots or Regional. Both those stages are round-robin only — players/teams are grouped (Grassroots: by venue, Regional: by region), each group plays a round robin, and the top N finishers (N is admin-configurable, not fixed) advance to the next stage. Knockout brackets only start at Circuit and Finals — one bracket per stage per category (Individual Male / Individual Female / Team), open to entrants from any region, capacity-capped (Circuit: 128 men / 64 women / 20 teams; Finals: 64 men / 32 women / 8 teams — these were already right in the design, unchanged).

**Design system**: keep using the existing tokens verbatim — ink/cue/gold palette, Mona Sans + IBM Plex Mono, the stage badge colors already defined in `design-system.md` §2.7 (Grassroots `cue-500` green, Regional `info` indigo, Circuit `gold-500`, Finals `ink-950`), the existing badge/pill, card, table, and button conventions in §6. Don't invent a new visual language for these additions — they should look like they were always part of this system.

---

## ADMIN APP screens (source file: `Cuevolution Admin.dc.html`)

The current admin sidebar nav is: Dashboard, Stages, Groups, Draws, Results & Points, Directory, Venues. "Stages" and "Groups" exist as *functioning screens in the app* but have **no design reference at all** — they were built ad hoc. Design them properly now. "Draws" and "Match results" (Results & Points) exist in the design file but need rework.

### 1. Stages (NEW — no existing design)

- Stage tabs across the top: Grassroots / Regional / Circuit / Finals, using the §2.7 stage badge colors.
- A "Participants" panel (default view): region + category filters, a list of participants in the selected stage with an "Advance" action per row that moves them to the next stage.
- A "Capacity / Group settings" panel (toggle or second tab), whose content depends on which stage is selected:
  - **Circuit/Finals selected**: capacity table — one row per category (Individual Male, Individual Female, Teams), showing current count / limit (e.g. "84 / 128"), inline-editable limit field, matches the existing admin inline-edit pattern (see Venue management's edit affordance).
  - **Grassroots/Regional selected**: a *different* small table — one row per category, two editable number fields per row: **Group size** (default 8) and **Top N advance** (default 2), same inline-edit interaction as the capacity table. Make clear via a caption or empty-state note that these stages are open/uncapped — this table configures round-robin format, not a capacity limit.

### 2. Groups (NEW — no existing design)

- Stage tabs: Grassroots / Regional only (no Circuit/Finals — they don't have groups).
- Region tabs (existing region set from the design system).
- **Grassroots only**: an additional venue selector nested under the selected region (venue list scoped to that region) — Grassroots groups are venue-scoped, Regional groups are region-scoped only.
- Category tabs: Individual Male / Individual Female / Teams — groups are single-category.
- A grid/list of group cards: group name, member roster (name + avatar/initials per the existing player-list pattern), an inline "create group" form (name field + submit), and an "add to group" control per card that picks from an "unassigned participants" list shown below the grid (same participant-row visual as the Directory list).
- Empty states: "No groups yet for {stage} · {venue-or-region} · {category}" and "Everyone in this stage/region is already grouped." (reuse the existing empty-state card pattern from Match results' "No fixtures for these filters").

### 3. Draws / Fixture entry (EXISTING — needs rework of the round-creation control only)

Keep everything else (the batch fixture-entry grid, live-search participant/venue comboboxes, "Already entered" list) exactly as designed. Only the "+ New round" control next to the round picker needs to become stage-aware:

- **Grassroots/Regional stage selected**: the new-round form shows a **group picker** dropdown (existing groups for that stage, labeled `{group name} · {venue-or-region} · {category}`) instead of a bare name field — a round always belongs to one group now.
- **Circuit/Finals stage selected**: the new-round form shows a **category picker** (Individual Male / Individual Female / Teams) instead — selecting a category and creating the round auto-attaches to that stage+category's single knockout bracket (created on first use). Round names at these stages read naturally as bracket rounds, e.g. "Round of 128," "Quarterfinal," "Final" — the name field stays free-text, just relabel the placeholder to hint at that (e.g. "Round of 64…").

### 4. Match results → rename "Results & Points" (EXISTING — significant rework)

Keep the Unplayed/Played tab chrome. Rework as follows:

- **Unplayed tab**: fixture list (as designed) + a result-entry panel on select: two radio rows (Participant A wins / Participant B wins, each showing the real participant name) and two optional number inputs for frame scores. Submit button "Save result."
- **Played tab is new** (the original design only had "Match results" with no correction/points flow):
  - Fixture list, same visual language as Unplayed, each row shows the recorded winner.
  - On select: a "Correct result" panel — same winner-radio pattern pre-filled with the current winner, **always preceded by a persistent amber warning banner**: "Correcting this result may affect standings and any stage advancement already made from it — review before saving." (use the `warning` semantic color, `amber-50` background per existing alert/banner treatment).
  - Below that, **only when the selected fixture's stage is Circuit or Finals**: a "Cuevo Points" section, one row per participant (name + a running total in gold per §2.4), each row either an "Add points" mini-form (number input + Add button) if no entry yet, or a pre-filled "Correct" mini-form if one exists. Grassroots/Regional fixtures never show this section — make that visually obvious (the section simply doesn't render, no "not applicable" placeholder needed).

### 5. Players & teams / Directory → player detail (EXISTING — one addition)

On the individual player detail view: add a destructive-styled "Anonymize player" button (danger/ghost-destructive, per §6.1) below the personal-details card. Clicking it reveals a confirm panel (amber warning card, same treatment as the results-correction banner) listing any applicable warnings as a bullet list — "This player is a team captain — anonymizing them does not reassign the captaincy" and/or "This player has a fixture with no result recorded yet" — with "Yes, anonymize" (destructive) and "Cancel" buttons. If neither warning applies, the panel instead reads a plain confirmation sentence. Once anonymized, the player's name badge shows an "ANONYMIZED" pill next to their name (muted/ink-400 tone, not a semantic color — it's a status, not an error).

---

## PLAYER APP screens (source file: `Cuevolution Player App.dc.html`)

### 1. Settings → Personal details card (EXISTING — region row needs two states)

The region row currently always shows a red "EDITABLE" badge + "You can still change your region — you haven't played a match yet." Split into two states:

- **Locked** (player has a recorded match result): a neutral/muted badge reading "LOCKED" (ink-100 background, ink-500 text — not a danger color, this isn't an error) + "Your region can't be changed — you've already played a match."
- **Editable** (unchanged from today): red "EDITABLE" badge + existing copy, but now paired with an actual region `<select>` dropdown beneath it (not just static text) that saves on change.

### 2. Standings (EXISTING — confirm/adjust column semantics, no structural change)

The table (#, Player/Team, Region, Played, W–L, Stage badge, Points) is still correct. Two things to make explicit in the design annotations:

- The **Points** column is Cuevo Points specifically — it's `0` (not blank/dash) for every Grassroots/Regional entrant, since Cuevo Points only start accruing at Circuit. Zero-point rows still rank and display, sorted to the bottom rather than hidden (per spec 009) — the footer caption already says "points in gold are Cuevo Points, earned from the Circuit stage onward," which is correct and should stay.
- This screen is now live — a points change from an admin session updates every connected player's standings view without a page reload. No visual change needed (the existing "Updated just now" timestamp label already implies this), but flag it in your design notes so it isn't "optimized away" as static content later.

---

## What NOT to touch

Landing page, registration/login/password-reset flow, Team dashboard, Fixtures (My fixtures) screen, Venue management, and Dashboard are unaffected by this round of changes — leave them as currently designed.

## Deliverable

Produce updated/new screens for each item above, matching the existing `Cuevolution Admin.dc.html` / `Cuevolution Player App.dc.html` files closely enough that they could be dropped back in as replacements. Keep every new screen visually indistinguishable in *style* from the existing ones — same nav chrome, same card/table/badge components, same spacing rhythm — only the content described above is new.
