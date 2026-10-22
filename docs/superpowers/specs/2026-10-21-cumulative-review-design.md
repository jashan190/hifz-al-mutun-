# Cumulative Review — Design

**Status:** approved design (brainstorming) — ready for implementation plan

**Goal:** Replace the compact, auto-pinned Session-Review card with a **persistent, cumulative review of a poem's flagged trouble-words**, reachable anytime from a footer button and shown in a roomy sheet.

**Core shift:** the review is no longer a one-off summary of the last sitting — it is a **per-matn list of every flagged word** (the cumulative record of where you've struggled), sourced from the already-persistent `FlagStore`. A sitting's mistakes feed it (they become flags) and enrich it with "you said X" while that sitting's summary is still in memory.

---

## 1. The footer button

A button lives in the reader footer **at all times** (read *and* memorize — there is empty space beside the mode toggle and the page counter):

- Label: "**مراجعة · N**" (Review · N) where **N = `flagStore.count(for: matn.id)`** — the number of flagged words for this matn. Updates live as flags are added/removed.
- When N == 0, still show the button (e.g. "مراجعة" with no count, slightly dimmed) so it's discoverable; tapping shows the empty state.
- Tapping sets `reviewPresented = true` (opens the sheet).
- Styled to the footer chrome (not a stock button); sits in the footer's spare space.

The old `SummaryCard` pinned in `.safeAreaInset(edge:.bottom)` is **removed**.

---

## 2. The review sheet (cumulative)

A `.sheet(isPresented: $reviewPresented)` at the large detent (`.presentationDetents([.large])`, drag indicator visible), leaving a sliver of the reader at the top.

**Header:** "المراجعة" (Review) title + Done (✕) — it's the poem's cumulative review, not a single session. Subtitle: "N flagged words" (or a clean "No flagged words yet" empty state).

**Body:** a full-height scrollable list of **every flagged word for this matn**, in reading order. Each row (a `MistakeCard`) is computed from the matn content at the flagged position:
- **Location** (prominent): `الحديث ٣` (prose) or `Bayt 12 · first half` (poem).
- **The word itself**, as written (from the matn content at that `FlagKey`).
- **If annotated (latest sitting only, see §4):** the differing letters marked + "you said X" / "skipped" / "added", exactly as the current `MistakeRow` renders.
- A chevron; the whole row is tappable.

**Row actions:**
- **Tap** → `reviewPresented = false`, then jump to that word's page and flash it (reuse the existing jump + `flashTarget` path; the jump target is the `FlagKey` → page, via the existing poem/prose page mapping).
- **Remove** (swipe-to-delete, or a trailing "Remove flag" button) → `flagStore.setFlag(false, …)`; the row drops off and the page's box clears.

**Footer of the sheet:** "Review again" (restart a sitting — the existing `reviewAgain`) and "Done" (dismiss). Styled to the app.

---

## 3. Resolving a `FlagKey` to a word + location

A pure helper maps the matn + its flagged `FlagKey`s into display rows, sorted in reading order:

```swift
struct ReviewItem: Identifiable {
    let key: FlagKey
    let word: String          // the flagged word, as written
    let location: String      // "الحديث ٣" / "Bayt 12 · first half"
    var id: FlagKey { key }
}
// func reviewItems(matn: Matn, flags: Set<FlagKey>) -> [ReviewItem]
```

- **Poem:** for a `FlagKey(bayt, half, wordIndex)`, find the `Bayt` with that number across `matn.pages`, pick `.sadr`/`.ajuz`, read `hemi.words[wordIndex].text`. Location = `"Bayt \(n) · first/second half"`.
- **Prose:** `bayt` = hadith number → `matn.hadiths.first { $0.number == bayt }`, `word = hadith.body[wordIndex].text`. Location = `"الحديث \(n)"`.
- Sort by `(bayt, half == .sadr ? 0 : 1, wordIndex)` so the list reads top-to-bottom. Skip (defensively) any key whose position no longer exists (out-of-range) — flags are position-keyed and the content is stable, but guard the array access.

This is the unit test target (pure, no UI).

---

## 4. Fresh-sitting annotation ("you said X")

"you said X" is ephemeral — only known from the sitting that produced it. The persistent list shows location + word always; it is **enriched only for the most recent sitting**:

- When `voice.summary` is non-nil, build a lookup `[FlagKey: ReviewSummary.Mistake]` from its `mistakes` (each `Mistake` carries `bayt/half/wordIndex` → a `FlagKey`, plus `expected/heard/added`).
- A `ReviewItem` whose `key` is in that lookup renders the richer `MistakeCard` (differing letters + "you said X"); otherwise it renders location + word only.
- After the sitting's summary is cleared (next sitting, or "Done" if we choose to clear it), those rows revert to location + word — correct, since the diff is gone.

**Auto-open after a sitting:** when a sitting stops and `voice.summary` becomes non-nil, set `reviewPresented = true` once (so you get immediate feedback). Thereafter the footer button reopens it. (An `.onChange(of: voice.summary != nil)` that opens on the nil→non-nil transition.)

---

## 5. Components & seams

- **New `ReviewSheet`** (`Features/Reader/`): the sheet content — header, the `ReviewItem` list, sheet footer. Takes the matn, the flagged `ReviewItem`s, the optional `[FlagKey: Mistake]` annotation map, and callbacks (`onSelect(FlagKey)`, `onRemove(FlagKey)`, `reviewAgain`, `done`).
- **`MistakeCard`** (`Features/Reader/`): one row as a card — reuses the current `MistakeRow`'s expected-word rendering (differing letters in `Theme.error`) and the enlarged location/word styling from the prior task; shows the "you said" line only when annotated.
- **`ReviewItems`** (pure, `Core/` or `Features/Reader/`): the `reviewItems(matn:flags:)` resolver (§3).
- **`PageScreen.swift`:** add the footer "Review · N" button; `@State reviewPresented`; present the `.sheet`; auto-open on sitting-end; wire `onSelect` → (dismiss + existing jump + `flashTarget`), `onRemove` → `flagStore.setFlag(false,…)`, `reviewAgain`/`done`. Remove the old `SummaryCard` from the bottom inset. The jump logic (poem `mistake.page` / prose `prosePage`) is reused, keyed by `FlagKey` → page: for poems, map `FlagKey.bayt` → the bayt's page via the existing index/`matn`; for prose, reuse `prosePage(hadith: key.bayt, wordInBody: key.wordIndex)`.
- **Reused unchanged:** `FlagStore`, `ReviewSummary`/`Mistake`, the box + `flashTarget` rendering, `LetterEmphasis`.

**Jump-target page from a `FlagKey`:** poems need `FlagKey.bayt → page`. The poem page of a bayt is `(bayt - 1) / matn.baytsPerPage + 1` (matn.page(ofBayt:) exists). Prose uses `prosePage(hadith:wordInBody:)`. Add a small `page(for key: FlagKey)` helper on PageScreen that branches on kind.

---

## 6. Scope

**In:** the persistent footer Review button (count), the large cumulative review sheet listing all flagged words (location + word), tap-to-jump+flash, remove-flag, fresh-sitting "you said X" annotation, auto-open after a sitting, removal of the old pinned card.

**Out (YAGNI):**
- Persisting "you said X" across app launches (ephemeral by design).
- Per-mistake "re-recite just this word" (possible later).
- Grouping/sectioning the list beyond reading order.
- Changing how flags are created (voice `syncFlags` and manual flagging are unchanged).

---

## 7. Testing

- **`reviewItems(matn:flags:)`** (pure): a poem matn + a set of flags → rows with correct word text, location strings, and reading-order sort (sadr before ajuz, by bayt then wordIndex); a prose matn + flags → correct hadith word + "الحديث N"; out-of-range/orphan keys are skipped without crashing.
- **Annotation map:** `[FlagKey: Mistake]` built from a `ReviewSummary` keys correctly (a mistake's bayt/half/wordIndex → FlagKey).
- **Empty state:** `reviewItems` on no flags → empty (UI shows the empty state).
- The sheet presentation, footer button, swipe-to-remove, and auto-open are verified on device.
