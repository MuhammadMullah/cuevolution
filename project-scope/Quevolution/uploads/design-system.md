# Cuevolution Design System

**Status**: Draft v1.0
**Created**: 2026-07-07
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

Per your direction, the neutral/"black" scale is grounded directly in **Dribbble's own production palette** (pulled from their live site CSS): their signature near-black is `#0D0C22` — a very dark indigo-black, not a pure black — used as their primary text/ink and dark-surface color, paired with a soft, warm-neutral gray ramp rather than cold grays.

We adopt that same ink anchor and neutral ramp as our foundation. For the **accent/brand color**, we did *not* carry over Dribbble's signature pink — that's their brand identity, not a neutral convention, and Cuevolution needs its own mark. Instead the accent is a **felt-table green** ("Cue Green"), which ties directly to the sport (pool table felt) and gives CTAs a distinct, ownable color separate from any reference site.

### 2.2 Ink / Neutral scale (Dribbble-anchored)

| Token | Hex | Source | Primary usage |
|---|---|---|---|
| `ink-25` | `#FDFCFB` | Dribbble CSS | Page background (warm off-white, not stark white) |
| `ink-50` | `#FAF9FB` | Dribbble CSS | Card/section background, subtle zebra striping |
| `ink-100` | `#F3F3F4` | Dribbble CSS | Muted surfaces, disabled fields, hover backgrounds |
| `ink-200` | `#E7E7E9` | Dribbble CSS | Borders, dividers |
| `ink-300` | `#DBDBDE` | Dribbble CSS | Stronger borders, input borders |
| `ink-400` | `#9E9EA7` | Dribbble CSS | Placeholder text, disabled text, icon default |
| `ink-500` | `#6E6D7A` | Dribbble CSS | Secondary/body-muted text |
| `ink-600` | `#524B63` | Dribbble CSS | Secondary headings |
| `ink-700` | `#3A3546` | Dribbble CSS | Primary body text (on light backgrounds) |
| `ink-900` | `#16152B` | interpolated | Dark surfaces (secondary), footer background |
| `ink-950` | `#0D0C22` | **Dribbble's exact "black"** | Primary headings, nav/header bar, primary button background, hero band background |

> Only `ink-800`/`ink-900` are interpolated to keep a smooth 10-step ramp — every other value is lifted verbatim from Dribbble's shipped CSS.

### 2.3 Cue Green — primary accent (brand, CTAs)

| Token | Hex | Usage |
|---|---|---|
| `cue-50` | `#EAFBF3` | Success/positive background tint |
| `cue-100` | `#CFF5E2` | Badge backgrounds (e.g., "Eligible" team status) |
| `cue-300` | `#7EDCB2` | Hover tint, chart fills |
| `cue-500` | `#189A63` | Secondary accent (links, active nav indicator) |
| `cue-600` | `#0F8354` | **Primary CTA** (Sign Up button, primary actions) |
| `cue-700` | `#0B6A44` | CTA hover/pressed state |
| `cue-900` | `#0A3F2A` | Text-on-tint (e.g., text inside a `cue-100` badge) |

### 2.4 Cuevo Gold — secondary accent (points, rank, achievement)

Pool halls trade in brass rails and trophy gold — reserved specifically for **Cuevo Points, rank #1 highlighting, and stage-advancement moments**, never for generic UI chrome, so it stays meaningful.

| Token | Hex | Usage |
|---|---|---|
| `gold-100` | `#FCEFCB` | Leader-row background tint in standings |
| `gold-500` | `#D9A02B` | Points values, trophy/rank-1 icon |
| `gold-700` | `#9C7318` | Text-on-tint |

### 2.5 Semantic colors

| Token | Hex | Usage |
|---|---|---|
| `success` | `cue-600` `#0F8354` | Form success, "sent" notification status |
| `warning` | `#D97706` | Non-blocking warnings (e.g., team below roster minimum) |
| `danger` | `#DC2626` | Validation errors (age < 18, duplicate username), destructive actions |
| `info` | `#5761B4` | Informational banners — this exact slate-indigo also comes from Dribbble's own `--btn-icon-color`/alert tokens, so it sits naturally alongside the ink ramp |

### 2.6 Usage rules

- **Never use color alone** to convey meaning (stage badges, eligibility, delivery status). Always pair with an icon or label — screen readers and colorblind users must get the same information (ties to NFR-8.1/accessibility).
- Default surface is **light** (`ink-25`/`ink-50`), with `ink-950` used deliberately as a dark band for the top nav, footer, and landing-page hero — mirroring how Dribbble itself uses its near-black as an occasional strong band rather than a full dark theme.
- Full dark-mode theming is **not** in MVP scope; token names are structured (`ink-*`, `cue-*`) so a dark variant can be added later without renaming.

### 2.7 Stage badge colors (Qualification Pipeline)

A fixed, memorable color per stage — used consistently everywhere a player's/team's stage appears (profile, standings, admin views):

| Stage | Token | Hex |
|---|---|---|
| Grassroots | `stage-grassroots` | `#189A63` (cue-500 — entry point, green) |
| Regional | `stage-regional` | `#5761B4` (info — mid-pipeline) |
| Circuit | `stage-circuit` | `#D9A02B` (gold-500 — points now matter) |
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
| `rounded-md` | 10px | Buttons, small cards |
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
| Primary | `bg-cue-600 text-white hover:bg-cue-700`, `rounded-md`, `shadow-sm` | Sign Up, primary form submits |
| Secondary | `bg-white text-ink-950 border border-ink-300 hover:bg-ink-50` | Sign In, secondary actions |
| Ghost | `text-ink-700 hover:bg-ink-100` | Tertiary/nav actions |
| Destructive | `bg-danger text-white hover:bg-red-700` | Remove player from team, deactivate venue |

All buttons: `px-4 py-2.5 text-sm font-medium` at base, `focus-visible:ring-2 ring-cue-500 ring-offset-2` for keyboard focus (never remove focus rings).

### 6.2 Forms & Validation

- Inputs: `rounded-sm border-ink-300 focus:border-cue-500 focus:ring-cue-500`.
- Inline, real-time validation (LiveView `phx-change`) per NFR-6.2: error text in `danger`, `text-sm`, appears directly beneath the field the moment it becomes invalid — no waiting for submit.
- Labels: `text-sm font-medium text-ink-700`, always visible (no placeholder-as-label).

### 6.3 Cards & Panels

Base card: `bg-white rounded-lg shadow-sm border border-ink-200 p-4 sm:p-6`. Used for: profile summary, team roster panel, admin stat tiles, landing-page feature cards.

### 6.4 Badges / Pills

`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium` with a semantic or stage color pairing (background tint + darker text tone, e.g. `bg-cue-100 text-cue-900` for "Eligible"). Always paired with a short label — never a color swatch alone (§2.6).

### 6.5 Tables

Used for standings and every admin data-entry screen (venues, draws, results, points):

- Sticky header row (`sticky top-0 bg-white`), `divide-y divide-ink-200`.
- Numeric columns (points, scores, dates) right-aligned, `font-mono tabular-nums`.
- Row hover: `hover:bg-ink-50`.
- Leader/rank-1 row in standings gets a `bg-gold-100` tint (§2.4), never gold text-only.
- On narrow screens, the table sits inside `overflow-x-auto` rather than collapsing to cards, so admins entering rounds of fixtures keep a consistent grid (supports NFR-6.3's "minimize manual steps, entered in volume").

### 6.6 Navigation

Three distinct nav contexts, same visual language:
- **Public/landing nav**: transparent-over-hero → solid `bg-ink-950` on scroll, with Sign In (ghost) + Sign Up (primary) always visible.
- **Player app nav**: `bg-white border-b border-ink-200`, simple top bar (Standings, My Team, Profile).
- **Admin console nav**: `bg-ink-950` persistent sidebar (Venues, Draws, Results & Points, Players & Teams, Notifications Log), `lg`+ only — collapses to a top bar with a drawer below `lg`.

### 6.7 Flash / Toasts

Leverages Phoenix's built-in flash mechanism, styled: success (`cue-50` bg / `cue-700` text), error (`red-50` bg / `danger` text), auto-dismiss after 5s with a manual close affordance, `rounded-lg shadow-md`, fixed top-right on `md`+, full-width top on mobile.

### 6.8 Stat Tiles (admin dashboard, standings summary)

`bg-white rounded-lg shadow-sm p-4`: a `text-xs text-ink-500` label over a large `text-2xl font-mono font-semibold text-ink-950` value — used for counts (registered players, active teams) and point leaders.

---

## 7. Landing Page Guidance

The landing page is the one fully public surface (scope §6: "no public site beyond in-app standings" refers to *competition data*, not the marketing/CTA page itself) and follows this structure:

1. **Hero** — `bg-ink-950` band, white Mona Sans headline (`text-5xl`/`text-6xl`), one-line subhead, primary CTA "Sign Up" (`cue-600`) + secondary "Sign In" (ghost, white border) side by side. Optional cue-green accent shape/texture evoking a felt table edge.
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
- All interactive elements keep a visible focus ring (`ring-cue-500`) — never `outline-none` without a replacement.
- Icons used alongside color for status/stage (§2.6) also carry an `aria-label` or adjacent text — never icon-only with no accessible name.
- Forms: every input has a associated `<label>`, error messages are linked via `aria-describedby`.

---

## 10. File Map

```text
design/
├── design-system.md     # This file
└── tokens.css           # Tailwind v4 @theme tokens — copy into assets/css/app.css
```

When implementation begins, `tokens.css`'s `@theme` block should be merged into the Phoenix app's `assets/css/app.css` (which already contains `@import "tailwindcss";`), making every token in this document available as a Tailwind utility (e.g. `bg-cue-600`, `text-ink-700`, `font-mono`).
