# Prose Voice Recitation — Design

**Status:** approved design (brainstorming) — ready for implementation plan

**Goal:** Extend the existing recite-to-reveal voice feature (currently working for the bayt poems) to the prose hadith (al-Arbaʿīn al-Nawawiyya), with fill-in-the-blanks reveal in the flowing justified paragraph and word-level mistake flagging.

**Scope (this spec):** recite-to-reveal, word-level mistakes (wrong / skipped / added), and the end-of-hadith review summary with jump-to-mistake — the full poem experience **minus** harakat/vowel-slip checking.

**Explicitly out of scope (YAGNI):** harakat/vowel-slip detection for prose (keeps us clear of the `PhonemeIndex` coverage work and the pre-existing bayqūniyya phoneme test), and **any change to the poem voice path** (the working feature must stay byte-for-byte in behaviour).

**Tech:** SwiftUI (iOS 26), Swift Testing, on-device WhisperKit speech, the existing `RecitationTracker` matcher.

---

## 1. Architecture — reuse the engine, add a thin prose layer

The voice stack is already in three tiers (confirmed by exploration):

- **Kind-agnostic core — REUSED AS-IS:** `SpeechSource` (WhisperKit / Mock / Silent), `RecitationSession` (pumps transcript fragments into the tracker), and `RecitationTracker` (the cursor/matching state machine over a flat `words: [String]`, producing `outcomes: [Int: WordOutcome]` keyed by flat index). None of this knows about bayts; it does not change.
- **Poem-specific layer — UNTOUCHED:** `RecitationIndex` (reads `matn.pages`→bayts → `WordRef(page,bayt,half,wordIndex)`), `RevealState`/`RevealLayout` (keyed on `(bayt, half)`), `MemorizeHalf`/`HemistichReveal` rendering, `ReviewSummary.Mistake(bayt,half)`.
- **Prose-specific layer — NEW (this spec):** a parallel index, reveal state, mistake type, and paragraph renderer.

**Approach chosen: parallel prose types, not a generic refactor.** Generalising `RevealState`/`VoiceController` to a kind-agnostic abstraction would touch the working poem code and risk regressions. Instead we add prose siblings and branch on `matn.kind` at the few call sites. The genuinely shared core (tracker/session/speech) is already generic, so the duplication is small and isolated.

---

## 2. Index — `ProseRecitationIndex` (`Core/Matching/`)

Flattens the hadith bodies into the same shape the tracker consumes:

```swift
struct ProseWordRef: Hashable {
    let hadith: Int        // 1-based hadith number
    let wordInBody: Int    // 0-based index within that hadith's body
}

struct ProseRecitationIndex {
    let normalizedWords: [String]   // ArabicNormalize.normalize of every body word, in order
    let displayWords: [String]      // the original (voweled) word, for mistake display
    let refs: [ProseWordRef]        // parallel to normalizedWords: flat index → (hadith, wordInBody)
    private let hadithStart: [Int: Int]   // hadith number → its first flat index

    init(hadiths: [Hadith])
    /// First flat index of a hadith (for starting a session mid-collection).
    func firstWordIndex(ofHadith n: Int) -> Int?
    /// Flat index of a specific body word (for reveal/outcome lookup).
    func flatIndex(hadith: Int, wordInBody: Int) -> Int?
}
```

Built from `matn.hadiths[].body` (NOT `matn.pages`, which is empty for prose). The `ProseWord.normalized` field already exists, so matching needs no new normalisation. Only the `matn` (words) is matched — the takhrīj is not part of the body and is never recited.

---

## 3. Engine — reused, with a prose branch in `VoiceController`

`RecitationSession`, `RecitationTracker`, and `SpeechSource` are unchanged — they already take a flat `[String]`. `VoiceController` (`Features/Reader/VoiceController.swift`) gains a prose path:

- **`start(...)`:** branch on `matn.kind`. For prose, build a `ProseRecitationIndex` and start the session at `firstWordIndex(ofHadith:)` for the hadith on the current page. PageScreen derives that hadith number from `currentPage` (the fragment shown there carries `hadithNumber`) and passes it in — the index itself needs no page knowledge. The `VowelChecker` is **not** attached for prose (scope).
- **Reveal output:** add `@Published var proseReveal: ProseRevealState?` alongside the existing `reveal: RevealState?`. For a prose matn the controller publishes `proseReveal`; the poem `reveal` stays `nil` (and vice-versa). Poem code reading `reveal` is untouched.
- **Summary:** `makeSummary` branches — for prose it maps each mistake's flat index through `ProseRecitationIndex.refs` into a `ProseMistake` (§6).
- **Reused unchanged:** `stop()`, `clear()`, `revealNext()` (tap-to-reveal), `fallBackToManual()`, `isLive`/`status`/`cursor`/`mistakeCount` publishing.

The matn is already held by the controller, so branching on `matn.kind` needs no new wiring.

---

## 4. Reveal state — `ProseRevealState` (`Features/Reader/`)

The poem `RevealState` is keyed on `(bayt, half)`. The prose equivalent is keyed on `(hadith, wordInBody)`, built from the tracker's flat `outcomes`/`heard`/`added` + the index's `(hadith, wordInBody) → flatIndex` map:

```swift
struct ProseRevealState {
    // built from ProseRecitationIndex + anchor/cursor/outcomes/heard/added
    func isRevealed(hadith: Int, wordInBody: Int) -> Bool   // flatIndex < cursor
    func outcome(hadith: Int, wordInBody: Int) -> WordOutcome?
    func heard(hadith: Int, wordInBody: Int) -> String?
    func added(hadith: Int, wordInBody: Int) -> String?
}
```

`WordOutcome` (the existing enum: `.correct`, `.unsure`, `.wrong(heard:)`, `.skipped`, `.unheard`, `.revealed`, `.shown`) is reused unchanged — only the colour mapping is applied in rendering.

---

## 5. Reveal rendering — "invisible ink" in the justified paragraph

The body stays the **same justified paragraph** `ProsePageView` already renders — we only drive each word's appearance by state, so the layout never reflows (each word keeps its real width; blanks "fill in"):

- **unrevealed** → foreground = page cream (invisible) + a thin underline cue.
- **revealed-correct** → ink (`Theme.ink`); **matn words** keep the subject colour when correct.
- **wrong** → red; **skipped** → grey; (other outcomes map to the existing memorize colours).

Generalise the shared attributed-string builder so measurement and both modes share one code path (width is colour-independent, so pagination is unaffected):

```swift
// ProseText
static func attributed(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                       color: (_ index: Int, _ role: ProseRole) -> UIColor,
                       underline: (_ index: Int) -> Bool) -> NSAttributedString
// read mode  : color = role→(ink|subject), underline = false   (today's look)
// memorize   : color = revealed ? outcome|subject : cream,      underline = !revealed
// measurement: color = .black, underline = false                (height identical)
```

`ProsePageView` takes an optional reveal context (the `ProseRevealState` + the fragment's `bodyStart`); in Memorize mode it renders via the memorize colour/underline closures, in Read mode the role colours (unchanged). The `JustifiedText` UILabel is reused; only its attributed string changes.

**Plumbing — `HadithFragment.bodyStart`:** add `let bodyStart: Int` (the index in the hadith body where this fragment's slice begins, set by `ProsePaginator`). A rendered word at fragment position `j` maps to `(hadith: fragment.hadithNumber, wordInBody: fragment.bodyStart + j)` for its reveal/outcome lookup.

---

## 6. Mistakes & summary

Add a prose mistake and surface it in the existing summary UI:

```swift
extension ReviewSummary {
    struct ProseMistake: Identifiable, Equatable {
        let id: Int            // flat word index
        let hadith: Int
        let wordInBody: Int
        let expected: String
        let heard: String?
        var added = false
    }
}
```

`SummaryCard` (and `ReviewSummary`) become kind-aware: for prose, rows read "الحديث N: التصحيح …" instead of "Bayt N · half". Tapping a mistake jumps to that word's page.

**Page mapping (auto-turn + mistake-jump) lives in `PageScreen`,** which owns `prosePages` (the runtime `HadithFragment`s). Given a `(hadith, wordInBody)` it finds the fragment where `frag.hadithNumber == hadith && frag.bodyStart <= wordInBody < frag.bodyStart + frag.words.count` → that page. The index deliberately does **not** store a page (prose paging is runtime), so `VoiceController.page(forCursor:)` stays poem-only; for prose, PageScreen maps `voice.cursor` → page itself using `prosePages` + the prose index refs.

---

## 7. Controls

Re-enable the Read/Memorize toggle and the mic for prose in `PageScreen`'s footer (they were hidden when prose was read-only). The gate becomes: controls shown for `.poem` **and** `.prose`. Memorize mode on a prose page now drives the fill-in-the-blanks reveal and (with the mic) live recognition; tap-to-reveal (`revealNext`) works as the no-mic fallback, same as poems.

---

## 8. Testing (Swift Testing)

- **`ProseRecitationIndex`:** flattening order, `normalizedWords`/`displayWords` parallel to `refs`, `firstWordIndex(ofHadith:)`, `flatIndex(hadith:wordInBody:)`; takhrīj excluded.
- **`ProseRevealState`:** `isRevealed` boundary at the cursor; `outcome`/`heard`/`added` lookups map correctly through the index.
- **Mistake mapping:** a set of flat outcomes → `ProseMistake`s with correct `(hadith, wordInBody, expected, heard)`.
- **`HadithFragment.bodyStart`:** paginator sets it so `bodyStart` of each fragment equals the running word offset (add to `ProsePaginatorTests`).
- **Reuse:** `RecitationTracker` is already covered; confirm it tracks a prose-derived word list in one integration-style test (feed hadith words, assert cursor/outcomes).
- Recognition accuracy and the visual reveal are verified on device.

---

## 9. File map

- **Create:** `Core/Matching/ProseRecitationIndex.swift`, `Features/Reader/ProseRevealState.swift`, tests.
- **Modify:** `Features/Reader/VoiceController.swift` (prose branch in `start`/`makeSummary`, `proseReveal` publish), `Features/Reader/ProseText.swift` (generalised `attributed`), `Features/Reader/ProsePageView.swift` (memorize reveal rendering), `Features/Reader/ProsePaginator.swift` + `Core/Models/Hadith.swift` (`HadithFragment.bodyStart`), `Features/Reader/PageScreen.swift` (re-enable controls, prose start/reveal wiring, cursor→page mapping), `Features/Reader/VoiceController.swift`/`SummaryCard` (`ProseMistake` + kind-aware rows).
- **Unchanged:** `RecitationTracker`, `RecitationSession`, `SpeechSource`/WhisperKit, `RecitationIndex`, `RevealState`, `MemorizeHalf`, poem rendering.
