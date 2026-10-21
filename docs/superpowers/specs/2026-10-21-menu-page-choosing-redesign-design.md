# Menu / Page-Choosing Redesign — Design Spec

**Date:** 2026-10-21
**Branch:** `ui-changes`
**Status:** Approved design, pending implementation plan
**Scope:** Roadmap item #1 of the UI changes batch.

## Overview

Redesign the app's navigation surfaces, in two parts:

- **Part A — Home (library):** replace the plain vertical list of poem cards with a subject-divided, visually rich "shelf" library that scales to many subjects (Qur'ān, Hadith, Seerah, ʿAqīdah, Arabic, Fiqh, and more), surfaces the user's active text for one-tap resume, and gives every poem a custom manuscript-style title-page cover.
- **Part B — In-reader sidecar:** replace the bottom "index" sheet with a right-edge overlay side panel for navigation (page/bayt jump + chapter list).

Both keep the app's existing calm, RTL, manuscript aesthetic (cream paper, Madinah green, Amiri text) and the existing design tokens in `Theme.swift` / `PageFont.swift`.

### Goals

- Home no longer feels plain; it reads as a curated library of mutun.
- Content is grouped by subject, extensible to new subjects without redesign.
- The daily task — resume the text I'm memorizing — is the first thing on screen.
- In-reader navigation stops hijacking the lower half of the screen; it becomes a side panel the reading page sits behind.

### Non-goals (this spec)

- No change to the reader page rendering itself (bayts, hemistich layout, Read/Memorize mode, mic/voice) beyond adding the sidecar trigger and removing the old index sheet.
- No new content authoring; we add a `subject` attribute to existing/new mutun.
- Actual cover art per poem beyond the templated title page (title + author + subject colour + ornament).

---

## Part A — Home (library) redesign

### A1. Content model / taxonomy

Add a **subject** concept so mutun can be grouped into shelves.

- Add `subject` to the `Matn` model (a stable identifier + display label), e.g. `subject: Subject` where `Subject` is an enum or lightweight struct with: `id` (e.g. `quran`, `hadith`, `seerah`, `aqeedah`, `arabic`, `fiqh`), Arabic display name, and an **accent colour**.
- Source of truth for the per-subject colour and label lives in one place (extend `Theme.swift` with a subject-colour map, or a `Subject` type that owns it). New subjects = one new entry.
- `ContentStore` currently auto-discovers `*.json` mutun and sorts by bayt count. Change it to **group by `subject`**, preserving a sensible within-subject order (bayt count ascending, as today). Subject section order is a fixed, defined list (so the shelf order is stable and intentional), with unknown/new subjects appended.
- JSON schema: add an optional `subject` field; mutun without it fall back to a default subject (e.g. Qur'ān/tajwīd) so existing content keeps working. Note this in the v2 schema docs.

**Per-subject colour palette (approved):**

| Subject | id | Hex |
|---|---|---|
| القرآن والتجويد | `quran` | `#15803D` |
| الحديث | `hadith` | `#C0362C` |
| السيرة | `seerah` | `#2A4FC4` |
| العقيدة | `aqeedah` | `#5A2E6B` |
| العربية | `arabic` | `#6B4A2A` |
| الفقه | `fiqh` | `#0E8E86` |

Colours are saturated/"loud" on purpose so the section is recognizable at a glance, including at small shelf sizes. These must have light/dark variants via the existing `Color.dynamic(light:dark:)` helper.

### A2. Layout — shelves + Continue card

Root library view (`RootView`), top to bottom, inside the existing `NavigationStack`:

1. **Header** — library title (منظومة/المكتبة) + settings button (unchanged behaviour).
2. **Continue card** (pinned, only when a last-read position exists):
   - Full-width card in the active matn's **subject colour**.
   - Shows: label (تابِع الحفظ / Continue), matn title (Aref Ruqaa), position (e.g. `صفحة ٣ · البيت ٤٢ من ١١٧٣`), a thin progress bar, and a resume affordance.
   - Tapping it opens that matn **at the exact last-read page** (reuses existing `ReadingPosition` / `lastPage.<matnID>`).
   - "Active matn" = the most recently read matn. Requires tracking most-recent-matn (a single `UserDefaults` key, e.g. `lastOpenedMatn`), in addition to the existing per-matn last page.
3. **Shelves** — one section per subject, in defined order:
   - Section header: subject name in the subject colour, with an `الكل ›` affordance (reserved for when a subject outgrows one row; MVP can show all in a wrapping/scrolling row).
   - A horizontally scrolling row (RTL) of **cover cards** for that subject's mutun.

Vertical scroll through subjects. The model is Apple-Books-like: browsable overview, every poem ~1 tap away, rich and colour-coded.

### A3. Cover (manuscript title page) component

A single reusable SwiftUI view, `MatnCover` (working name), parameterized by: `title`, `author`, `baytCount` (or `نثر` for prose), subject `accentColor`, and a top cartouche label (`منظومة` for poems, `متن` for prose). Used at two sizes: **hero** (Continue card / detail) and **shelf** (~110–120 pt wide). Replaces today's `MatnCard`.

Visual composition (all tinted by the subject colour):

- **Ground:** cream paper (`#F4EBD3`, dynamic for dark mode).
- **Texture:** a faint diamond cross-hatch (diagonal lattice) tiled behind the content at very low opacity (~0.16). Implement as a tiling pattern/`Canvas` or a small repeated asset.
- **Border:** a thin double-rule frame in the subject colour, inset from the card edge.
- **Corner ornament:** a floral corner motif in each corner (mirrored), **edges-only** (hugs the corner, trails modestly along the edges, never into the middle), **middle weight** — solid blooms with translucent (~0.3 opacity) leaf fills, recoloured to the subject colour. Source: a CC0 (OpenClipart) corner SVG, brought in as a template asset and tinted; petals given body rather than left as hairline outlines.
- **Content (centered):** cartouche label (Amiri) → **title in Aref Ruqaa** (subject colour) → author line (Amiri, muted ink) → bayt/line count at the base (subject colour).

**Fonts:** titles **Aref Ruqaa**; all supporting text **Amiri** (already bundled). Aref Ruqaa must be added to the bundle and registered alongside the existing Amiri registration in `PageFont`/app font setup. (Aref Ruqaa is SIL OFL — safe to bundle.)

**Scaling note:** the ornament/frame should map cleanly to any card size. Treat the border + corners as a **9-slice** (fixed corners, edges that stretch/tile) rather than scaling the whole frame, so the corner flowers never distort between hero and shelf sizes.

---

## Part B — In-reader sidecar

Replaces the current bottom index sheet (`IndexSheet` in `PageScreen`).

- **Form:** a side panel (sidecar) that **opens from the right edge** (RTL-leading), as an **overlay** — it slides over the reader and the page dims behind it (scrim). Not a push.
- **Trigger:** the header **☰ / index button** (right side of the header). Explicitly **not** an edge-swipe, because the reader turns pages with a horizontal swipe (`TabView`, RTL) and an edge-swipe would fight that gesture.
- **Dismiss:** tap the scrim, tap ✕ in the panel header, or (optionally) swipe the panel off toward the right edge.
- **Width:** ~80% of screen width on a phone (leaves a sliver of dimmed page visible).

**Panel contents (top to bottom):**

1. **Header:** matn title (Aref Ruqaa) + ✕ close, on a Madinah-green bar.
2. **Jump control:** a segmented **صفحة / بيت** switch, then a number field + a green "go" button. Reuses the existing page/bayt jump logic (today's two `NumberStepperField`s), condensed.
3. **الأبواب (chapters):** a scrollable list of `Bab`s (title + start page `ص N`), each tappable to jump to that chapter's start page. The **current chapter is highlighted** (subject-colour tint + leading marker). Uses the existing `matn.babs`.

The Read/Memorize toggle and mic stay in the footer (not moved into the sidecar).

---

## Assets, fonts, licensing

- **Aref Ruqaa** font files (SIL OFL) — add to bundle + register.
- **Floral corner ornament** — one CC0/OpenClipart corner SVG, imported as a template/tintable asset, mirrored into four corners.
- **Diamond hatch** — generated pattern (no external asset needed) or a tiny repeated tile.
- Add any new fonts to the app's font registration path and `Info.plist` (`UIAppFonts`) as the existing Amiri fonts are.

## Affected areas (verify exact files during planning)

- `App/RootView.swift` — library layout: header + Continue card + shelves; replaces the `MatnCard` list.
- New `MatnCover` view (+ supporting ornament/hatch/border views) — the title-page cover.
- `Core/Content/ContentStore.swift` — group mutun by subject; subject ordering.
- `Core/Content/Matn.swift` (model) — add `subject`; JSON decoding + v1→v2 fallback.
- `Core/Design/Theme.swift` — subject colour palette (light/dark).
- `Core/Design/PageFont.swift` / app font setup — register Aref Ruqaa.
- Reading position — add "most recently opened matn" tracking for the Continue card.
- `Features/Reader/PageScreen.swift` — replace `IndexSheet` with the new right-edge sidecar overlay; wire the ☰ trigger; keep page/bayt jump + bab-jump logic.
- New `ReaderSidecar` view.

## Build/tooling note

The `.xcodeproj` is **generated by XcodeGen** (`xcodegen generate`) and is gitignored. New source files, font files, and assets must be added via the XcodeGen project spec and regenerated, not by hand-editing the project — otherwise a regenerate wipes them. Confirm the XcodeGen spec is the source of truth before adding files.

## Open questions / decisions deferred to implementation

- Exact "active matn" rule for the Continue card (strictly most-recent, or most-recent-not-finished).
- Whether `الكل ›` per-subject "see all" screen is in this pass or a follow-up (MVP: show all mutun in the row).
- Dark-mode exact shades for each subject colour.
- Final corner-ornament flower density (one tunable value; current ~0.3 petal opacity).

## Verification

- Build + run in the Simulator (per working style), checking: home shelves render RTL and colour-coded; Continue card resumes to the exact page; covers render with Aref Ruqaa titles and legible at shelf size; sidecar opens from the right over a dimmed page, jumps by page/bayt, and chapter taps navigate with the current chapter highlighted.
- Final sign-off on device.
