# Cuevolution Design System

**Status**: Draft v1.2
**Created**: 2026-07-07
**Updated**: 2026-07-09 — accent recolored to Kenya Red/Green (from the Kenya Pool Billiard Federation logo), pill buttons, neutral leader-row tint, corrected pipeline stage colors
**Applies to**: The entire product surface — the public landing page (CTAs: Sign Up / Sign In, about-the-league content, community, partners), player-facing app (registration, team, standings), and the admin console (venues, draws, results, points).
**Stack context**: Phoenix LiveView + Tailwind CSS v4. Tokens in this document are written to drop directly into `assets/css/app.css` via a Tailwind v4 `@theme` block — see [`tokens.css`](./tokens.css).

---

## 1. Design Principles

1. **Modern, clean, sleek** — generous whitespace, restrained color usage, soft elevation instead of heavy borders/shadows.
2. **Mobile-first** — the majority of players will register and check standings from a phone on Kenyan mobile networks (NFR-6.1, NFR-8.2). Every component is designed at its smallest breakpoint first.
3. **Data-legible** — this is fundamentally a *standings and results* product. Numeric data (Cuevo Points, scores, rankings, dates/times) must be immediately scannable, which drives the tabular/mono type choice below.
4. **One visual language everywhere** — the landing page, player app, and admin console share the same tokens and components. The admin console is denser (more tables, more form fields per screen) but never a different "skin."
5. **Real-time feels alive, not jumpy** — LiveView-driven updates (standings ticking up, inline validation) use short, calm transitions, never layout-jank.

---

## 2. Color

### 2.1 Where this comes from

The neutral/"black" scale is a warm, near-indigo-black ink — `#0D0C22` — used as ink-950: our primary text/ink and dark-surface color, paired with a soft, warm-neutral gray ramp rather than cold grays. Black is the primary brand color everywhere: nav bars, primary buttons, the hero band.

For the **accent colors**, we draw directly from the **Cuevolution / Kenya Pool Billiard Federation logo**: a strong **Kenya Red** and a **Kenya Green**, each expanded into its own tonal scale so they can carry tints, hover states and text-on-tint pairings. Kenya Red is the secondary accent (links, active states, highlights); Kenya Green is reserved for success, "eligible" status, and the Regional pipeline stage. Cuevo Gold remains a narrow, separate accent used only for points and rank.

### 2.2 Ink / Neutral scale (warm near-black)

| Token | Hex | Source | Primary usage |
|---|---|---|---|
| `ink-25` | `#FDFCFB` | brand ramp | Page background (warm off-white, not stark white) |
| `ink-50` | `#FAF9FB` | brand ramp | Card/section background, subtle zebra striping |
| `ink-100` | `#F3F3F4` | brand ramp | Muted surfaces, disabled fields, hover backgrounds; also the standings leader/hover/active row tint (§6.5) |
| `ink-200` | `#E7E7E9` | brand ramp | Borders, dividers |
| `ink-300` | `#DBDBDE` | brand ramp | Stronger borders, input borders |
| `ink-400` | `#9E9EA7` | brand ramp | **On light backgrounds (white/`ink-25`/`ink-50`): decorative use only** — dividers, large icon glyphs, chart gridlines. Computed contrast against white is ~2.66:1, which fails WCAG AA for text (4.5:1) and even the 3:1 floor for UI components — do not use for placeholder or disabled *text* on light surfaces; use `ink-500` instead (~5.08:1, passes AA). **On dark backgrounds (`ink-950`/`ink-900`): safe for text** — contrast against `ink-950` is ~7.23:1, which is why the footer (§7) uses it for secondary text. *The light-background misuse was caught and corrected during system design review §4.1.* |
| `ink-500` | `#6E6D7A` | brand ramp | Secondary/body-muted text; also the Grassroots stage color and the `info` semantic |
| `ink-600` | `#524B63` | brand ramp | Secondary headings |
| `ink-700` | `#3A3546` | brand ramp | Primary body text (on light backgrounds) |
| `ink-900` | `#16152B` | interpolated | Dark surfaces (secondary), footer background |
| `ink-950` | `#0D0C22` | **primary brand black** | Primary headings, nav/header bar, primary button background, hero band background |

> Only `ink-900` is interpolated to keep a smooth ramp — every other value is a deliberately warm (not cold) gray.

### 2.3 Kenya Red — secondary accent (links, active states, CTAs)

Drawn straight from the Cuevolution / Kenya Pool Billiard Federation logo mark.

| Token | Hex | Usage |
|---|---|---|
| `red-50` | `#FDECEA` | Error/alert background tint |
| `red-100` | `#FBD5D0` | Badge/tint backgrounds |
| `red-300` | `#F09B92` | Hover tint |
| `red-500` | `#E32219` | **Primary CTA & secondary accent** (Sign Up button, links, active nav indicator, focus ring) |
| `red-600` | `#C81E16` | CTA hover/pressed state |
| `red-700` | `#A81810` | Text-on-tint (e.g., text inside a `red-100` badge) |
| `red-900` | `#5E0D08` | Deepest tint, rarely used |

### 2.3b Kenya Green — tertiary accent (success, eligibility)

Also drawn from the logo. Reserved for success states, "eligible" team status, and the Regional pipeline stage — never a general-purpose UI color.

| Token | Hex | Usage |
|---|---|---|
| `green-50` | `#F0FAF3` | Success background tint |
| `green-100` | `#DCF3E4` | Badge backgrounds (e.g., "Eligible" team status, Regional stage) |
| `green-300` | `#7FD6A0` | Hover tint, chart fills |
| `green-500` | `#16A34A` | Success accent, Regional stage color |
| `green-600` | `#128F40` | Hover/pressed state |
| `green-700` | `#0E6A30` | Text-on-tint |
| `green-900` | `#093E1C` | Deepest tint, rarely used |

### 2.4 Cuevo Gold — secondary accent (points, rank, achievement)

Pool halls trade in brass rails and trophy gold — reserved specifically for **Cuevo Points, rank #1 highlighting, and stage-advancement moments**, never for generic UI chrome, so it stays meaningful.

| Token | Hex | Usage |
|---|---|---|
| `gold-100` | `#FCEFCB` | Reserved for future gold-tint use (currently unused — leader-row tint is `ink-100`, see §6.5) |
| `gold-500` | `#D9A02B` | Points values, trophy/rank-1 icon |
| `gold-700` | `#9C7318` | Text-on-tint |

### 2.5 Semantic colors

| Token | Hex | Usage |
|---|---|---|
| `success` | `green-500` `#16A34A` | Form success, "sent" notification status |
| `warning` | `#D97706` | Non-blocking warnings (e.g., team below roster minimum) |
| `danger` | `#DC2626` | Validation errors (age < 18, duplicate username), destructive actions |
| `info` | `ink-500` `#6E6D7A` | Informational banners — kept in the black/red/green/gray family rather than introducing a fifth hue |

### 2.6 Usage rules

- **Never use color alone** to convey meaning (stage badges, eligibility, delivery status). Always pair with an icon or label — screen readers and colorblind users must get the same information (ties to NFR-8.1/accessibility).
- Default surface is **light** (`ink-25`/`ink-50`), with `ink-950` used deliberately as a dark band for the top nav, footer, and landing-page hero rather than a full dark theme.
- Full dark-mode theming is **not** in MVP scope; token names are structured (`ink-*`, `red-*`, `green-*`) so a dark variant can be added later without renaming.

### 2.7 Stage badge colors (Qualification Pipeline)

A fixed, memorable color per stage — used consistently everywhere a player's/team's stage appears (profile, standings, admin views):

| Stage | Token | Hex |
|---|---|---|
| Grassroots | `stage-grassroots` | `#6E6D7A` (ink-500 — entry point, neutral) |
| Regional | `stage-regional` | `#16A34A` (green-500 — qualifiers open) |
| Circuit | `stage-circuit` | `#E32219` (red-500 — points now matter) |
| Finals | `stage-finals` | `#0D0C22` (ink-950 — the top) |

---

## 3. Typography

### 3.1 Font families

| Role | Family | Rationale |
|---|---|---|
| **Primary (UI + headings + body)** | **Mona Sans** (variable), fallback `"Inter", "Helvetica Neue", Arial, sans-serif` | This *is* Dribbble's own production font — a modern, geometric, highly legible variable sans by GitHub, open source (SIL OFL 1.1), free to self-host. It reads as contemporary/design-forward without being a generic system font, fitting the "modern, clean, sleek" brief. |
| **Numeric / tabular data** | **IBM Plex Mono**, fallback `Menlo, Consolas, monospace` | Also lifted from Dribbble's own stack, but used here deliberately: standings, Cuevo Points, match scores, and dates/times are the emotional core of this product, and a monospaced numeral set keeps columns of numbers aligned and instantly scannable in tables. Applied narrowly — headings and body copy stay in Mona Sans. |

**Self-hosting note**: Mona Sans and IBM Plex Mono are not on Google Fonts — both are open-license and should be self-hosted as `.woff2` under `priv/static/fonts/` and declared via `@font-face` in `app.css`, per NFR-8.2 (works on low/mid bandwidth — self-hosted variable fonts subset to Latin only keep payload small).

### 3.2 Type scale

Applied via Tailwind's default `text-*` utilities, mapped to these `rem` values (1rem = 16px):

| Token | Size / Line-height | Usage |
|---|---|---|
| `text-xs` | 0.75rem / 1rem | Timestamps, helper text, table meta |
| `text-sm` | 0.875rem / 1.25rem | Secondary body, form labels, table cells |
| `text-base` | 1rem / 1.5rem | Body copy |
| `text-lg` | 1.125rem / 1.75rem | Lead paragraph, card titles |
| `text-xl` | 1.25rem / 1.75rem | Section sub-headings |
| `text-2xl` | 1.5rem / 2rem | Page titles (admin/app) |
| `text-3xl` | 1.875rem / 2.25rem | Landing page section headings |
| `text-4xl` | 2.25rem / 2.5rem | Landing page sub-hero |
| `text-5xl`–`text-6xl` | 3rem–3.75rem / 1.1 | Landing page hero headline only |

- Headings: Mona Sans, weight 600–700 (semibold/bold), `tracking-tight`.
- Body: Mona Sans, weight 400–500.
- Numeric data (points/scores/dates in tables): IBM Plex Mono, weight 500, `tabular-nums`.

---

## 4. Spacing, Radius & Elevation

### 4.1 Spacing

Use Tailwind's default 4px base spacing scale as-is (`p-1`…`p-96`) — no custom override. Component-level conventions:

- Section vertical rhythm (landing page): `py-16` mobile → `py-24` desktop.
- Card padding: `p-4` mobile → `p-6` desktop.
- Form field vertical gap: `space-y-4`.

### 4.2 Radius

A softly rounded, modern feel — never sharp corners, never fully pill-shaped except for pills/avatars/badges themselves.

| Token | Value | Usage |
|---|---|---|
| `rounded-sm` | 6px | Inputs, checkboxes |
| `rounded-md` | 10px | Small cards, non-button surfaces (buttons always use `rounded-full` — see §6.1) |
| `rounded-lg` | 16px | Cards, modals, panels |
| `rounded-xl` | 24px | Hero media, large feature cards |
| `rounded-full` | 9999px | Avatars, badges/pills, stage chips |

### 4.3 Elevation

Shadows are soft and low-contrast — the ink ramp's own tones are used instead of pure black at low opacity, keeping shadows feeling warm rather than muddy:

| Token | Value |
|---|---|
| `shadow-sm` | `0 1px 2px rgba(13,12,34,0.06)` |
| `shadow-md` | `0 4px 12px rgba(13,12,34,0.08)` |
| `shadow-lg` | `0 12px 32px rgba(13,12,34,0.12)` |

Use `shadow-sm` for resting cards, `shadow-md` on hover/focus, `shadow-lg` reserved for modals/popovers only.

---

## 5. Layout & Breakpoints

Tailwind's default breakpoints, used mobile-first throughout (NFR-6.1, NFR-8.1):

| Breakpoint | Width | Primary target |
|---|---|---|
| (default) | 0–639px | Phones — the primary registration/standings surface |
| `sm` | ≥640px | Large phones/small tablets |
| `md` | ≥768px | Tablets, admin console minimum comfortable width |
| `lg` | ≥1024px | Laptops — admin console primary target |
| `xl` | ≥1280px | Desktops, landing page full layout |

**Rules**:
- No fixed pixel widths on any component; containers use `max-w-*` + `mx-auto` with fluid padding (`px-4 sm:px-6 lg:px-8`).
- Tables (standings, admin draw/results entry) scroll horizontally within their own container on narrow screens (`overflow-x-auto`) rather than squeezing columns unreadably.
- Admin data-entry screens (draws, results, points — entered "in volume, per round" per NFR-6.3) are designed lg-first for efficiency, but must remain usable down to `md`.

---

## 6. Core Components

All components below are Tailwind utility compositions (no separate component CSS framework) — implemented as Phoenix `core_components.ex` function components / LiveView function components so they're reused identically across landing, player, and admin surfaces.

### 6.1 Buttons

| Variant | Style | Usage |
|---|---|---|
| Primary | `bg-ink-950 text-white hover:bg-ink-900`, `rounded-full` (pill), `shadow-sm` | Sign Up, primary form submits |
| Secondary | `bg-white text-ink-950 border border-ink-300 hover:bg-ink-100`, `rounded-full` | Sign In, secondary actions |
| Ghost | `text-ink-700 hover:bg-ink-100`, `rounded-full` | Tertiary/nav actions |
| Destructive | `bg-danger text-white hover:bg-red-700`, `rounded-full` | Remove player from team, deactivate venue |

Every button — every variant, every surface — uses a **full pill radius** (`rounded-full`), never `rounded-md`. All buttons: `px-4 py-2.5 text-sm font-medium` at base, `focus-visible:ring-2 ring-red-500 ring-offset-2` for keyboard focus (never remove focus rings). **Disabled**: `disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none` on any variant — never convey "disabled" through color/opacity alone without the `disabled` attribute itself, so assistive tech announces it correctly.

### 6.2 Forms & Validation

- Inputs: `rounded-sm border-ink-300 focus:border-red-500 focus:ring-red-500`. Placeholder text: `placeholder:text-ink-500` (not `ink-400` — see §2.2). **Disabled inputs**: `disabled:bg-ink-100 disabled:text-ink-500 disabled:cursor-not-allowed`.
- Inline, real-time validation (LiveView `phx-change`) per NFR-6.2: error text in `danger`, `text-sm`, appears directly beneath the field the moment it becomes invalid — no waiting for submit.
- Labels: `text-sm font-medium text-ink-700`, always visible (no placeholder-as-label).
- **Profile picture / file uploads** (registration, spec 003): show upload progress inline (LiveView's native upload progress), and fall back to an initials-based avatar (`bg-ink-950 text-white`, first-and-last-initial) anywhere a profile picture is referenced but not yet set — never a broken image icon.

### 6.3 Cards & Panels

Base card: `bg-white rounded-lg shadow-sm border border-ink-200 p-4 sm:p-6`. Used for: profile summary, team roster panel, admin stat tiles, landing-page feature cards.

### 6.4 Badges / Pills

`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium` with a semantic or stage color pairing (background tint + darker text tone, e.g. `bg-green-100 text-green-700` for "Eligible"). Always paired with a short label — never a color swatch alone (§2.6).

### 6.5 Tables

Used for standings and every admin data-entry screen (venues, draws, results, points):

- Sticky header row (`sticky top-0 bg-white`), `divide-y divide-ink-200`.
- Numeric columns (points, scores, dates) right-aligned, `font-mono tabular-nums`.
- Row hover: `hover:bg-ink-50`.
- Leader/rank-1 row in standings gets a **neutral `bg-ink-100` tint**, not a gold tint — this same tint is reused for row hover/active states, so rank #1 reads as "the current focus row," not a garish highlight. Rank #1's point value itself still renders in gold (§2.4) and the row carries a left accent bar in red-500; never gold background.
- On narrow screens, the table sits inside `overflow-x-auto` rather than collapsing to cards, so admins entering rounds of fixtures keep a consistent grid (supports NFR-6.3's "minimize manual steps, entered in volume").
- **Any table with an uncapped row count — public standings (Grassroots is open-entry, spec 009) and the admin player/team directory (spec 010) — MUST be built with `Phoenix.LiveView.stream/3`, not a plain assign.** A plain assign holding hundreds of rows is re-diffed and re-sent on every update — including the PubSub-driven live updates standings already require — which is the standard LiveView memory/performance pitfall for exactly this kind of growing list. Capped tables (a single group's fixtures, a team's 5–8 roster) can stay as plain assigns.

### 6.6 Navigation

Three distinct nav contexts, same visual language:
- **Public/landing nav**: transparent-over-hero → solid `bg-ink-950` on scroll, with Sign In (ghost) + Sign Up (primary) always visible.
- **Player app nav**: `bg-white border-b border-ink-200`, simple top bar (Standings, My Team, Profile).
- **Admin console nav**: `bg-ink-950` persistent sidebar (Venues, Draws, Results & Points, Players & Teams, Notifications Log), `lg`+ only — collapses to a top bar with a drawer below `lg`.

### 6.7 Flash / Toasts

Leverages Phoenix's built-in flash mechanism, styled: success (`green-50` bg / `green-700` text), error (`red-50` bg / `danger` text), auto-dismiss after 5s with a manual close affordance, `rounded-lg shadow-md`, fixed top-right on `md`+, full-width top on mobile.

### 6.8 Stat Tiles (admin dashboard, standings summary)

`bg-white rounded-lg shadow-sm p-4`: a `text-xs text-ink-500` label over a large `text-2xl font-mono font-semibold text-ink-950` value — used for counts (registered players, active teams) and point leaders.

### 6.9 Loading & Empty States

Neither state was covered in the original draft of this document (system design review §4.2) — both are common enough in this product (standings loading, an admin filtering the directory to zero results, a brand-new region with no venues yet) to need a fixed convention rather than being improvised per-screen:

- **Loading/skeleton**: for tables and cards awaiting data (standings on first load, an async-assigned admin panel), show a pulsing skeleton in the same shape as the eventual content (`animate-pulse bg-ink-100 rounded-md`) rather than a generic spinner — it prevents layout shift when real content arrives. A centered spinner (`animate-spin`, `text-red-500`) is acceptable only for full-page transitions (e.g., initial login redirect).
- **Empty state**: centered within the content area, an `ink-400`-or-lighter icon (large-scale use, §2.2), a `text-ink-700` one-line message (e.g., "No venues yet for this region"), and — where the admin can act on it — a primary button to resolve it directly (e.g., "Add a venue"). Never leave a table/list rendering as a bare empty `<table>` with only a header row.

---

## 7. Landing Page Guidance

The landing page is the one fully public surface (scope §6: "no public site beyond in-app standings" refers to *competition data*, not the marketing/CTA page itself) and follows this structure:

1. **Hero** — `bg-ink-950` band, white Mona Sans headline (`text-5xl`/`text-6xl`), one-line subhead, primary CTA "Sign Up" (`red-500`, pill) + secondary "Sign In" (ghost, white border, pill) side by side. Optional Kenya red/green accent shape evoking the logo mark.
2. **About Cuevolution** — 2–3 short paragraphs / stat tiles (regions covered, stages in the pipeline) on `ink-25` background.
3. **The Pipeline** — a horizontal (desktop) / vertical (mobile) visual of Grassroots → Regional → Circuit → Finals using the stage badge colors from §2.7, so a first-time visitor learns the pipeline via the same color language they'll see once logged in.
4. **The Pool Community** — testimonial-style or photo-grid cards (`rounded-xl`, `shadow-md`) representing regions/players.
5. **Partners** — a simple logo strip, grayscale by default (`grayscale opacity-70 hover:grayscale-0 hover:opacity-100 transition`), on `ink-50`.
6. **Footer** — `bg-ink-950`, white/`ink-400` text, secondary nav + legal links.

All sections share the same `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8` container and `py-16 sm:py-24` rhythm from §4.1.

---

## 8. Motion

- Standard transition: `transition-all duration-150 ease-out` for hover/focus states.
- LiveView-driven updates (standings changing, flash appearing): `duration-200 ease-out`, fade + slight slide (`opacity` + `translate-y-1`), never an abrupt content swap.
- Respect `prefers-reduced-motion: reduce` — disable non-essential transitions/animations for users who request it.

---

## 9. Accessibility

- Minimum contrast: body text (`ink-700` on `ink-25`/white) and inverse text (white on `ink-950`) both exceed WCAG AA for normal text; verify any new color pairing against AA before use.
- All interactive elements keep a visible focus ring (`ring-red-500`) — never `outline-none` without a replacement.
- Icons used alongside color for status/stage (§2.6) also carry an `aria-label` or adjacent text — never icon-only with no accessible name.
- Forms: every input has a associated `<label>`, error messages are linked via `aria-describedby`.

---

## 10. Media & Bandwidth

Not covered in the original draft (system design review §4.4) despite NFR-8.2's low/mid-bandwidth requirement:

- **Profile pictures** (spec 003 registration): resized server-side to a fixed maximum (e.g., 512×512) and re-encoded on upload — never store or serve the original, potentially multi-megabyte camera file. Serve a smaller derivative (e.g., 96×96) anywhere the picture appears in a list (standings, team roster, admin directory) rather than downscaling a full-size image in the browser.
- **Lazy-loading**: avatar/profile images in any list view use `loading="lazy"`.
- **Partner/sponsor logos** (landing page §7.5): served as compressed SVG or WebP, not unoptimized PNG exports.
- **Fonts**: Mona Sans and IBM Plex Mono are self-hosted (§3.1) and should be subset to Latin glyphs only to keep the variable-font payload small on first load.

## 11. Localization

The product targets Kenya, where Swahili is widely spoken alongside English, but neither the scope document nor the requirements document asks for a bilingual interface. **Decision for MVP: English-only.** This is stated here explicitly (system design review §4.5) so it reads as a conscious scope boundary rather than an oversight — if Swahili support becomes a requirement later, using Phoenix's built-in `Gettext` from the start of implementation (rather than hardcoding UI strings) keeps that door open cheaply.

---

## 12. File Map

```text
design/
├── design-system.md     # This file
└── tokens.css           # Tailwind v4 @theme tokens — copy into assets/css/app.css
```

When implementation begins, `tokens.css`'s `@theme` block should be merged into the Phoenix app's `assets/css/app.css` (which already contains `@import "tailwindcss";`), making every token in this document available as a Tailwind utility (e.g. `bg-cue-600`, `text-ink-700`, `font-mono`).
