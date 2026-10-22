# Mistake Highlighting & Session Review — Design

**Status:** approved design (brainstorming) — ready for implementation plan

**Goal:** Make memorization mistakes visible and clear: flagged words show a persistent red *box* (not red text) on the page, cleared by long-press; the Session Review points precisely at each mistake; and the mistake-red no longer blends into the hadith's red content text.

**Core principle:** A mistake is marked by a **red box, never by recoloring the glyphs**. The box is a distinct visual channel, so it reads clearly on black poem text *and* on red hadith matn text. This single decision fixes the colour clash and provides the persistent marker.

---

## 1. The box & colour

A flagged word gets a **soft red rounded highlight box**: fill `Theme.error` at low opacity (~0.12), a thin `Theme.error` border (~0.5 opacity), small corner radius. The word's **text colour is unchanged** (black/ink for poems, `subject.accent` red for hadith matn, the normal tokens for poems).

- `Theme.error` (`#C62828` light / `#EF6B6B` dark) is the "signal-red", already used for live wrong words — deliberately distinct from the content reds `Theme.rumuz` (`#B02430`) and `subjectAccent(.hadith)` (`#C0362C`). Because the box is a separate channel from the glyphs, even a red matn word inside a red box stays legible and the box stays obviously a "mistake" marker.
- This **replaces** the current easy-to-miss burnt-orange underline (`Theme.flag`) for flagged words in read mode. `Theme.flag` may remain for any non-mistake affordance, but flagged mistakes now use the box.

A small reusable style expresses the box so poems and the Session-Review flash share one definition, e.g. a `MistakeBox` view modifier / shape config: `cornerRadius`, `fill = Theme.error.opacity(0.12)`, `stroke = Theme.error.opacity(0.5)`, `lineWidth ~1`.

---

## 2. Where it shows (persistent, read mode)

Boxes render **in read mode**, driven by the existing `FlagStore` (SwiftData, keyed by `FlagKey(bayt, half, wordIndex)`; `bayt` = hadith number and `half = .sadr` for prose — already how flags are stored). Memorize mode shows live outcomes, not persistent flag boxes: poems' live colouring is unchanged; prose's live mistake treatment is addressed in §5.

**Poems** (`Features/Reader/PageView.swift`, `BaytRow` read-mode hemistich): the hemistich already computes per-word character ranges (`HemistichText.wordRanges`) and already filters `flagged(which, k)`. Add a per-word **SwiftUI rounded box behind each flagged word** (a `.background` keyed to the word's measured sub-rect, or an overlay of boxes positioned from the word ranges). Remove/replace the flagged underline with the box.

**Hadith** (`Features/Reader/ProsePageView.swift` → `JustifiedText` `UILabel`): the body is one justified label, so per-word SwiftUI boxes aren't available. Draw the boxes **inside the label** using TextKit: for each flagged word's character range, get its glyph rect(s) from the layout and draw a rounded red box behind the glyphs (a `UILabel` subclass that overrides `draw(_:)`, or a background layer computed from `NSLayoutManager`/`NSTextLayoutManager` bounding rects for the flagged ranges). The paragraph stays justified; only backgrounds are added. `ProsePageView` passes the set of flagged word-in-body indices for the fragment (from `FlagStore`) plus the `bodyStart` offset so the label knows which of its words are flagged.

Both read from `FlagStore.isFlagged(matnID, key)` at render time (the in-memory cache makes this cheap), so boxes appear/disappear reactively as flags change.

---

## 3. Long-press to clear

Long-press a boxed (flagged) word → remove the flag; the box disappears (`FlagStore.setFlag(false, …)`), persisted immediately.

- **Poems:** attach the gesture to the per-word box (a `.contextMenu`/long-press on the box region targeting that word's `FlagKey`) offering **"Remove flag"**. The existing hemistich-level context menu (which lists words to flag/unflag) stays as the way to *add* a flag by hand; the box gives a direct per-word *remove*.
- **Hadith:** the `UILabel` hit-tests the long-press point to a character index (TextKit `characterIndex(for:)`), maps it to the word-in-body → `FlagKey`, and if that word is flagged offers **"Remove flag"** (a `UIContextMenuInteraction` or long-press recognizer on the label). If the pressed word isn't flagged, no-op (or offer "Flag" for parity — optional, see §6).

---

## 4. Session Review — point at the mistake

`SummaryCard` / `MistakeRow` (`Features/Reader/PageScreen.swift`) and the `show(mistake)` jump:

1. **Flash the word on jump.** Tapping a mistake row jumps to its page (existing) **and** triggers a transient **red-box pulse** on that exact word. Add a short-lived `@State flashTarget: FlagKey?` (or `(bayt, half, wordIndex)`) on `PageScreen`, set when a row is tapped, passed down to the page rendering; the matching word draws the mistake box with a brief scale/opacity pulse, then `flashTarget` clears after ~1.2s. This reuses the §1 box style. Works for poems and (via the label's flagged-range drawing with a transient index) hadith.
2. **Bigger expected-vs-heard.** Enlarge/clarify the "should be X · you said Y" line in `MistakeRow` — larger type, the expected word and the heard word visually contrasted (expected in ink with its differing letters marked, heard in signal-red or quoted). Keep the existing data (`expected`, `heard`, `added`, `skipped`).
3. **More prominent location.** Make the `الحديث ٤` / `Bayt 23 · first half` label larger/bolder so each mistake's place is scannable at a glance.

No mistake counter (explicitly out — user choice).

---

## 5. Prose live-review mistakes

During recitation (Memorize mode) in a hadith, a `.wrong` word currently colours its text `Theme.rumuz` (red) — which blends with red matn text. Change prose live mistakes to the **box treatment + `Theme.error`**: the wrong word gets the signal-red box (and/or signal-red text via the existing `ProsePageView.wordColor`, switched from `Theme.rumuz` to `Theme.error`), so a mistake on a red matn word is still obvious. `.skipped`/`.unheard` keep the dim treatment. Poems' live colour-coding is unchanged (no clash on non-red poem text).

(Drawing a live-mistake box in the prose label reuses the §2 TextKit box drawing, driven by the live reveal outcomes for the current fragment rather than `FlagStore`.)

---

## 6. Scope

**In:** the red box marker (§1), persistent read-mode boxes for poems + hadith (§2), long-press-to-clear (§3), the three Session-Review clarity improvements (§4), and the prose live-mistake colour fix (§5).

**Out (YAGNI):**
- Persisting *what* was said wrong with a flag — flags stay location-only; the "what" lives in the improved Session Review (shown right after a sitting).
- Mistake counter in the review.
- Persistent *flag* boxes in Memorize mode — memorize shows live outcome colours (poems) and the §5 live mistake box (prose); the persistent read-mode flag boxes are a review aid and don't appear in memorize.
- Adding a "Flag" action via the hadith long-press is optional; the primary hadith long-press target is *removing* an existing flag.

---

## 7. Components & seams

- **`MistakeBox`** (new small view/shape config, `Features/Reader/`): the shared box look (fill/stroke/radius), used by poem boxes and the review flash.
- **`Core/Design/Theme.swift`**: reuse `Theme.error`; no new token needed (if a dedicated `mistakeBox` fill/stroke pair is cleaner, add it here with the comment tying it to the error red).
- **`PageView.swift` (BaytRow read mode)**: per-word flag box + per-word long-press remove; replace the flagged underline.
- **`ProsePageView.swift` / `JustifiedText`**: a `UILabel` that draws rounded boxes behind given word ranges (flagged from `FlagStore` in read mode; wrong-outcome words in memorize), and hit-tests long-press → word → remove flag.
- **`PageScreen.swift` (`SummaryCard`/`MistakeRow` + `show` closure)**: flash target state + pulse, bigger expected-vs-heard, prominent location.
- **`FlagStore.swift`**: reused as-is (`isFlagged`, `setFlag`); no schema change.

## 8. Testing

- **FlagStore** behaviour is already covered; add a test only if a new query is introduced (none planned).
- **Word-range → box mapping (poems):** a pure test that, given a hemistich's word ranges and a flagged set, yields the right word sub-ranges to box.
- **Prose flagged-range resolution:** a pure test mapping `FlagStore` flags for a hadith + a fragment's `bodyStart`/word count → the set of local word indices to box (no UILabel needed).
- **Flash lifecycle:** a test that `flashTarget` sets on row tap and clears after the interval (if extracted into a small testable controller), else verified on device.
- Box appearance, long-press hit-testing, and the label drawing are verified on device.
