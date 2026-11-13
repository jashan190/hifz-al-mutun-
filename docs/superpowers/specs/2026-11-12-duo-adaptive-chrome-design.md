# iPhone Duo adaptive reader chrome — design

**Date:** 2026-11-12
**Branch:** `duo-support`
**Status:** approved, implementing

## Goal

Make the matn reader feel built for the iPhone Duo (foldable). Replace the fixed
top header + bottom footer with a single control component that changes position
by device state, fix verse centering on the large inner screen in portrait, and
make the index panel a sane width instead of 80% of the screen.

Regular iPhones and iPad are **unchanged** — this is Duo-only.

## The three Duo states

Driven by a single resolver combining **hinge capability** (is this a Duo?),
**size classes**, and **orientation**:

| Condition | State | Chrome | Pages | Index |
|-----------|-------|--------|-------|-------|
| No hinge (regular iPhone / iPad) | — | **unchanged** header + footer | existing | existing 80% |
| Hinge + compact width | Duo **cover** | vertical rail (trailing edge) | single | fixed ~320pt |
| Hinge + regular×regular + landscape (w>h) | Duo **inner landscape** | vertical rail (trailing edge) | two-page spread | fixed ~320pt |
| Hinge + regular×regular + portrait (h>w) | Duo **inner portrait** | bottom bar | single, **centered column** | fixed ~320pt |

**Duo detection:** use the iOS 27.1 hinge API — if `onHingeChange` / hinge
interaction is unavailable (nil) the device does not fold, so it is not a Duo and
we fall through to the existing header+footer path. This is what keeps the cover
screen (which otherwise looks like a regular compact-width iPhone) from changing
behaviour on real iPhones.

## Components

### `ReaderChrome` (new)

One component that renders all reader controls. Extracted from the current
`topBar` + `footer` in `PageScreen.swift`.

- **Contents, same order in every state:** back · index · mode toggle ·
  mic *(memorize mode only)* · review (مراجعة) · page indicator. **No title.**
- **Two presentations:**
  - **Vertical rail:** trailing/right edge, **~52pt** wide (44pt HIG tap target +
    padding — deliberately slim, not chunky). Buttons stack top-down; page
    indicator at the bottom (vertical text). Prefer the native
    `toolbarVerticalEdge` / `verticalBarEdge` affordance where it fits.
  - **Bottom bar:** the current footer layout, reused as-is.
- Uses the subject `chrome` colour exactly as today.
- Honors `barsVisible` (tap page to hide) in all states.

### Header removal

The `topBar` is deleted. Its two buttons (back-to-library, index) move into
`ReaderChrome`. The current chapter name becomes a **small running head** at the
top of the page content (quiet, book-like); the full matn title + chapter live in
the index panel header (already there).

### Index panel (`ReaderSidecar`) width

Replace `width: geo.size.width * 0.8` with a **fixed ~320pt** panel (standard
regular-width sidebar), clamped so it never exceeds ~85% on the narrow cover
screen. Spread stays visible and dimmed behind it; tap scrim to close. Content of
the sidecar is unchanged.

### Verse centering (portrait bug fix)

In `PageView`, cap the verse content to a **maximum readable width**
(≈ `min(availableWidth, 680pt)`) and **center** that column, so a wide inner-screen
portrait page gets equal left/right margins instead of verses drifting to one
edge. `columnWidth` / font sizing derive from the capped width. Two-page spread
pages are already narrow enough that the cap is a no-op there.

### State persistence across fold/unfold

`currentPage` and `mode` must survive a fold/unfold/rotate. These are already
`@State` on `PageScreen`; verify they are not reset when the resolver flips
presentation, and that page clamping on geometry change (existing logic) keeps the
same logical page.

## Fold avoidance (polish)

In the two-page spread, use `ReservedRegion` / `reservedRegions` so the center
divider and any content stay clear of the physical fold/camera occlusion.

## Scope / non-goals

- **In:** Duo cover + inner (both orientations), the four points above.
- **Out:** any change to regular iPhone or iPad chrome; new reading features;
  TestFlight pipeline changes; Mac/visionOS.

## Implementation phases (build + run after each)

1. **Hinge detection + state resolver** — add `ReaderLayout` enum + a resolver
   that reads hinge capability, size classes, orientation. No visual change yet;
   verify it reports the right state via an on-screen debug label on each Duo state.
2. **Extract `ReaderChrome`** — pull current footer controls + the header's two
   buttons into one component rendering the **bottom bar** presentation. Wire it
   so non-Duo keeps the exact current header+footer look. Build; confirm regular
   iPhone unchanged.
3. **Vertical rail presentation** — add the rail layout to `ReaderChrome`; show it
   in Duo cover + inner-landscape. Delete the `topBar`; move chapter to running
   head. Build; check on Duo simulator (cover + landscape).
4. **Index panel width** — fixed ~320pt. Build; check on all Duo states.
5. **Verse centering** — cap + center the column. Build; check Duo inner portrait
   and that spread/phone/iPad are unaffected.
6. **Fold avoidance + state-persistence verification + polish.** Build; full pass
   across cover / landscape / portrait and a regular iPhone regression check.

## Testing

- Manual on the iPhone Duo simulator for each state (DeviceHub fold/unfold).
- Regression: run on a regular iPhone simulator — header+footer must be identical
  to `main`.
- Where logic is unit-testable (the state resolver), add a small test over
  (hinge, sizeClass, orientation) → `ReaderLayout`.
