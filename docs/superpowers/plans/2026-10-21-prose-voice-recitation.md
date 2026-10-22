# Prose Voice Recitation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the working recite-to-reveal voice feature to the prose hadith — recite a hadith and watch the blanks fill in (invisible-ink), with word-level mistakes and an end-of-hadith review summary. No harakat checking.

**Architecture:** Reuse the voice engine *and* the poem reveal/session machinery unchanged by modeling **each hadith as one "bayt" unit whose single `.sadr` half holds all its words**. `RecitationIndex`, `RecitationSession`, `RecitationTracker`, `RevealState`, and `VoiceController` are already keyed on a generic `(bayt, half, wordIndex)` tuple and a flat word list — so feeding them hadith words (bayt = hadith number, half = `.sadr`) needs only an additive prose branch in `RecitationIndex`, plus prose-specific *rendering* and page-mapping. The poem path is untouched (its branch of `RecitationIndex.init` and all downstream code are unchanged).

**Tech Stack:** SwiftUI (iOS 26), Swift Testing, on-device WhisperKit, the existing `RecitationTracker`. Build/test sim id `0F8C82CA-6844-40E1-B260-9F1024DB07EC` (iOS 26.5; find another via `-showdestinations`; ignore the "IOSurfaceClientSetSurfaceNotify" line). Device UDID `83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941`. Run `xcodegen generate` after adding files.

**Spec:** `docs/superpowers/specs/2026-10-21-prose-voice-recitation-design.md` (note: architecture refined to the reuse approach above — same UX: fill-in-the-blanks invisible-ink, words-first, start from the current hadith).

**Key reused facts (from the real code):**
- `WordRef { page:Int, bayt:Int, half:Half, wordIndex:Int }`; `Half { .sadr, .ajuz }`.
- `RecitationIndex` has `normalizedWords`, `displayWords`, `refs`, `firstWordIndex(ofBayt:)`, `firstWordIndex(onPage:)`; built in `init(matn:)` by iterating `matn.pages`→`.bayt` items.
- `RevealState` queries: `revealedWords(bayt:half:)`, `outcome(bayt:half:wordIndex:)`, `heard(...)`, `added(...)`, `holdsCursor(bayt:half:)`, `flatIndex(bayt:half:wordIndex:)`. Reused as-is.
- `VoiceController.start(matn:fromPage:bayt:flags:manual:)` seeds at `firstWordIndex(ofBayt:)` when `bayt` is given → **passing the current hadith number as `bayt` starts a prose session at that hadith**.
- `ReviewSummary.Mistake { id, page, bayt, half, expected, heard, added }` — for prose, `bayt` carries the hadith number.
- `ArabicNormalize.normalize(_:)` is the shared normaliser.

---

## File map

- **Modify:** `Core/Matching/RecitationIndex.swift` (prose branch in `init`), `Core/Models/Hadith.swift` (`HadithFragment.bodyStart`), `Features/Reader/ProsePaginator.swift` (set `bodyStart`), `Features/Reader/ProseText.swift` (generalise `attributed`), `Features/Reader/ProsePageView.swift` (memorize reveal rendering), `Features/Reader/VoiceController.swift` (`ref(forCursor:)` accessor; kind-aware summary labelling stays data-only), `Features/Reader/PageScreen.swift` (re-enable controls for prose, prose start, cursor→page mapping, pass reveal), `Features/Reader/PageScreen.swift`'s `SummaryCard` (kind-aware mistake row text).
- **Test:** `Tests/MatchingTests/RecitationIndexProseTests.swift`, additions to `Tests/MatchingTests/ProsePaginatorTests.swift` and `Tests/MatchingTests/ProseTextTests.swift`.

---

## Task 1: `RecitationIndex` builds from prose hadith

Model each hadith as a bayt (number = hadith number) with a single `.sadr` half holding its body words. Poems are unchanged.

**Files:** Modify `Core/Matching/RecitationIndex.swift`; Test `Tests/MatchingTests/RecitationIndexProseTests.swift`.

- [ ] **Step 1: Write the failing test** — Create `Tests/MatchingTests/RecitationIndexProseTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct RecitationIndexProseTests {
    private func proseMatn() -> Matn {
        let h1 = Hadith(number: 1, title: "الحديث الأول",
                        body: [ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
                               ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn)],
                        takhrij: "رواه")
        let h2 = Hadith(number: 2, title: "الحديث الثاني",
                        body: [ProseWord(text: "بَيْنَمَا", normalized: "بينما", role: .matn)],
                        takhrij: "")
        return Matn(id: "p", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "", subject: .hadith, kind: .prose, hadiths: [h1, h2],
                    baytsPerPage: 0, pageCount: 0, baytCount: 2, pages: [], babs: [], reviewNotes: [])
    }

    @Test func flattensHadithBodiesInOrder() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.normalizedWords == ["عن", "انما", "بينما"])
        #expect(index.displayWords == ["عَنْ", "إِنَّمَا", "بَيْنَمَا"])
    }

    @Test func refsCarryHadithAsBaytAndWordInBody() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.refs.map(\.bayt) == [1, 1, 2])          // hadith number
        #expect(index.refs.allSatisfy { $0.half == .sadr })    // single half
        #expect(index.refs.map(\.wordIndex) == [0, 1, 0])      // index within body
    }

    @Test func firstWordIndexOfHadith() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.firstWordIndex(ofBayt: 1) == 0)   // bayt == hadith number
        #expect(index.firstWordIndex(ofBayt: 2) == 2)
    }

    @Test func poemIndexUnchanged() {
        // A bayt poem still flattens sadr-then-ajuz as before.
        let bayt = Bayt(number: 1,
                        sadr: Hemistich(text: "a b", segments: [], words: [Word(text: "a", normalized: "a"), Word(text: "b", normalized: "b")]),
                        ajuz: Hemistich(text: "c", segments: [], words: [Word(text: "c", normalized: "c")]))
        let page = MatnPage(page: 1, items: [.bayt(bayt)])
        let m = Matn(id: "q", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                     meter: "الرجز", subject: .quran, kind: .poem, hadiths: [],
                     baytsPerPage: 10, pageCount: 1, baytCount: 1, pages: [page], babs: [], reviewNotes: [])
        let index = RecitationIndex(matn: m)
        #expect(index.normalizedWords == ["a", "b", "c"])
        #expect(index.refs.map(\.half) == [.sadr, .sadr, .ajuz])
    }
}
```

- [ ] **Step 2: Run the test — verify it FAILS** (prose matn yields an empty index today).

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' -only-testing:HifzAlMutunTests/RecitationIndexProseTests`
Expected: the three prose tests fail (empty `normalizedWords`/`refs`); `poemIndexUnchanged` passes.

- [ ] **Step 3: Add the prose branch** — In `RecitationIndex.init(matn:)`, wrap the existing `for page in matn.pages { ... }` loop so prose takes a new path. Replace the body of `init` from `var words...` through the loop with:

```swift
        var words: [String] = []
        var display: [String] = []
        var refs: [WordRef] = []
        var pageStart: [Int: Int] = [:]
        var baytStart: [Int: Int] = [:]

        if matn.kind == .prose {
            // Each hadith is one "bayt" unit (bayt = hadith number); all its body
            // words live in the .sadr half. The reveal/session machinery is unit-
            // agnostic, so this reuses it unchanged. `page` is 0 here — prose pages
            // are computed at runtime (ProsePaginator), so PageScreen maps a word's
            // page, not this index.
            for hadith in matn.hadiths {
                baytStart[hadith.number] = words.count
                for (wi, w) in hadith.body.enumerated() {
                    words.append(ArabicNormalize.normalize(w.text))
                    display.append(w.text)
                    refs.append(WordRef(page: 0, bayt: hadith.number, half: .sadr, wordIndex: wi))
                }
            }
        } else {
            for page in matn.pages {
                pageStart[page.page] = words.count
                for item in page.items {
                    guard case .bayt(let bayt) = item else { continue }
                    baytStart[bayt.number] = words.count
                    for (half, hemi) in [(Half.sadr, bayt.sadr), (Half.ajuz, bayt.ajuz)] {
                        for (wi, word) in hemi.words.enumerated() {
                            words.append(ArabicNormalize.normalize(word.text))
                            display.append(word.text)
                            refs.append(WordRef(page: page.page, bayt: bayt.number,
                                                half: half, wordIndex: wi))
                        }
                    }
                }
            }
        }

        self.normalizedWords = words
        self.displayWords = display
        self.refs = refs
        self.pageStart = pageStart
        self.baytStart = baytStart
```

(Keep the existing `firstWordIndex(ofBayt:)` / `firstWordIndex(onPage:)` methods as-is.)

- [ ] **Step 4: Run the tests — verify all PASS** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Matching/RecitationIndex.swift Tests/MatchingTests/RecitationIndexProseTests.swift
git commit -m "RecitationIndex: build from prose hadith (hadith as bayt unit)"
```

---

## Task 2: `HadithFragment.bodyStart` so rendered words map to outcomes

A page shows a slice of a hadith; to look up a word's reveal/outcome we need its index within the full body. Add `bodyStart` (the body offset of the fragment's first word) and have the paginator set it.

**Files:** Modify `Core/Models/Hadith.swift`, `Features/Reader/ProsePaginator.swift`; Test add to `Tests/MatchingTests/ProsePaginatorTests.swift`.

- [ ] **Step 1: Add a failing test** — In `Tests/MatchingTests/ProsePaginatorTests.swift`, add inside the suite:

```swift
    @Test func fragmentsCarryBodyStartOffset() {
        // 15-word hadith over 2 pages (bodyHeight 10, heading 2 → 8 then 7).
        let (pages, _) = ProsePaginator.paginate(
            [hadith(1, words: 15)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(frag(pages[0]).bodyStart == 0)
        #expect(frag(pages[1]).bodyStart == 8)   // second page resumes after the first 8 words
    }
```

- [ ] **Step 2: Run it — verify it FAILS** (`HadithFragment` has no `bodyStart`).

- [ ] **Step 3: Add the field** — In `Core/Models/Hadith.swift`, add to `HadithFragment`:

```swift
struct HadithFragment: Hashable {
    let hadithNumber: Int
    let title: String
    let words: [ProseWord]
    let takhrij: String
    let isFirst: Bool
    let isLast: Bool
    /// Index in the full hadith body of this fragment's first word, so a rendered
    /// word maps back to its (hadith, wordInBody) position for reveal/outcome.
    var bodyStart: Int = 0
}
```

- [ ] **Step 4: Set it in the paginator** — In `Features/Reader/ProsePaginator.swift` `paginate`, track the running offset. In the `for h in hadiths` loop, reset a counter per hadith and set it on each fragment:

```swift
        for h in hadiths {
            firstPageOf[h.number] = pageNo + 1
            var rest = h.body
            var first = true
            var consumed = 0                      // words of this hadith already paged
            repeat {
                pageNo += 1
                let cap = max(1, bodyHeight - (first ? headingHeight : 0))
                let n = max(1, fit(rest, cap: cap, measure: measureBody))
                let slice = Array(rest.prefix(n))
                rest = Array(rest.dropFirst(n))
                let isLast = rest.isEmpty
                pages.append(MatnPage(page: pageNo, items: [.hadith(
                    HadithFragment(hadithNumber: h.number, title: h.title,
                                   words: slice, takhrij: h.takhrij,
                                   isFirst: first, isLast: isLast, bodyStart: consumed))]))
                consumed += slice.count
                first = false
            } while !rest.isEmpty
        }
```

- [ ] **Step 5: Run the paginator tests — verify all PASS** (existing + the new one).

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProsePaginatorTests`

- [ ] **Step 6: Commit**

```bash
git add Core/Models/Hadith.swift Features/Reader/ProsePaginator.swift Tests/MatchingTests/ProsePaginatorTests.swift
git commit -m "HadithFragment: bodyStart offset so words map to reveal positions"
```

---

## Task 3: `ProseText.attributed` — per-word colour/underline (for invisible-ink)

Generalise the shared attributed-string builder so read mode, memorize (reveal) mode, and measurement share one path. Width is colour-independent, so pagination is unaffected.

**Files:** Modify `Features/Reader/ProseText.swift`; Test add to `Tests/MatchingTests/ProseTextTests.swift`.

- [ ] **Step 1: Add a failing test** — In `Tests/MatchingTests/ProseTextTests.swift`, add:

```swift
    @Test func attributedAppliesPerWordColourAndUnderline() {
        let a = ProseText.attributed(words, font: .systemFont(ofSize: 20), lineSpacing: 8,
            color: { i, _ in i == 0 ? .green : .red },
            underline: { i in i == 1 })
        #expect(a.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .green)
        let i2 = (a.string as NSString).range(of: "إِنَّمَا").location
        #expect(a.attribute(.foregroundColor, at: i2, effectiveRange: nil) as? UIColor == .red)
        #expect((a.attribute(.underlineStyle, at: i2, effectiveRange: nil) as? Int ?? 0) != 0)
        #expect((a.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
    }
```

- [ ] **Step 2: Run it — verify it FAILS** (`attributed` doesn't exist / wrong signature).

- [ ] **Step 3: Implement** — In `Features/Reader/ProseText.swift`, add the general builder and make `body` a thin wrapper:

```swift
    /// The body as a justified RTL paragraph, each word styled by closures so the
    /// same builder serves read mode, memorize (reveal) mode, and measurement
    /// (colour/underline don't affect layout, so heights match across modes).
    static func attributed(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                           color: (_ index: Int, _ role: ProseRole) -> UIColor,
                           underline: (_ index: Int) -> Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineSpacing = lineSpacing
        para.baseWritingDirection = .rightToLeft
        let out = NSMutableAttributedString()
        for (i, w) in words.enumerated() {
            if i > 0 {
                out.append(NSAttributedString(string: " ",
                    attributes: [.font: font, .foregroundColor: color(i, w.role), .paragraphStyle: para]))
            }
            var attrs: [NSAttributedString.Key: Any] =
                [.font: font, .foregroundColor: color(i, w.role), .paragraphStyle: para]
            if underline(i) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: w.text, attributes: attrs))
        }
        return out
    }
```

And change the existing `body(...)` to delegate (keeps measurement + read-mode callers working):

```swift
    static func body(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                     isnad: UIColor, matn: UIColor) -> NSAttributedString {
        attributed(words, font: font, lineSpacing: lineSpacing,
                   color: { _, role in role == .matn ? matn : isnad },
                   underline: { _ in false })
    }
```

- [ ] **Step 4: Run — verify PASS** (new test + the existing `bodyColoursByRoleAndJustifies`).

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProseTextTests`

- [ ] **Step 5: Commit**

```bash
git add Features/Reader/ProseText.swift Tests/MatchingTests/ProseTextTests.swift
git commit -m "ProseText: per-word colour/underline builder for invisible-ink reveal"
```

---

## Task 4: `ProsePageView` renders the fill-in-the-blanks reveal

In Memorize mode, drive each word's colour/underline from the `RevealState` (keyed on bayt = hadith number, half = `.sadr`, wordIndex = bodyStart + position). Read mode is unchanged.

**Files:** Modify `Features/Reader/ProsePageView.swift`. No unit test (view) — verified by build + Task 7 device check.

- [ ] **Step 1: Add reveal inputs + memorize rendering** — In `ProsePageView`, add properties and branch the body. Replace the struct's stored properties and `body`'s `JustifiedText(...)` call:

```swift
struct ProsePageView: View {
    let fragment: HadithFragment
    let subjectColor: Color
    var fontSize: CGFloat = proseBodyFontSize
    /// Memorize mode: the live reveal (nil ⇒ plain read mode).
    var reveal: RevealState? = nil

    static func lineSpacing(for fontSize: CGFloat) -> CGFloat { fontSize * 0.5 }

    /// The `.sadr` half holds the hadith's whole body, so `revealedWords` is a
    /// prefix count over it: a word at body index `w` is shown iff `w < that`.
    private func shown(_ j: Int) -> Bool {
        guard let reveal else { return true }   // read mode: all shown
        return (fragment.bodyStart + j) < reveal.revealedWords(bayt: fragment.hadithNumber, half: .sadr)
    }
    private func wordColor(_ j: Int, _ role: ProseRole) -> UIColor {
        let base = role == .matn ? UIColor(subjectColor) : UIColor(Theme.ink)
        guard let reveal else { return base }               // read mode
        guard shown(j) else { return UIColor(Theme.cover) } // not yet reached → invisible ink
        switch reveal.outcome(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j) {
        case .wrong: return UIColor(Theme.rumuz)            // said wrong
        case .skipped, .unheard: return UIColor(Theme.ink.opacity(0.35))
        default: return base                                // correct / revealed / shown
        }
    }
    private func wordUnderline(_ j: Int) -> Bool { reveal != nil && !shown(j) }
```

Then the body's paragraph:

```swift
            JustifiedText(attributed: ProseText.attributed(
                fragment.words,
                font: PageFont.uiFont(size: fontSize),
                lineSpacing: Self.lineSpacing(for: fontSize),
                color: { j, role in wordColor(j, role) },
                underline: { j in wordUnderline(j) }))
                .frame(maxWidth: .infinity)
```

Change `JustifiedText` to take a prebuilt `attributed: NSAttributedString` (simpler than the words/colours params it has now): update its stored properties to `let attributed: NSAttributedString`, `updateUIView` sets `label.attributedText = attributed`, and `sizeThatFits` measures `attributed`. Update the read-mode caller likewise (it can keep using `ProseText.body(...)` wrapped: `JustifiedText(attributed: ProseText.body(...))`).

- [ ] **Step 2: Build (sim)** — fix compile errors; confirm `RevealState` is visible to `ProsePageView` (same module).

Run: `xcodegen generate && xcodebuild build -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' 2>&1 | grep -E "error:|BUILD SUCCEEDED" | head`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ProsePageView.swift
git commit -m "ProsePageView: invisible-ink reveal rendering in Memorize mode"
```

---

## Task 5: `VoiceController` — expose the cursor's hadith for page mapping; kind-aware summary

The controller already works with a flat index whose refs now carry (bayt = hadith, wordIndex = wordInBody) for prose. Add an accessor PageScreen needs, and confirm the summary carries the hadith number (it already does, via `bayt`).

**Files:** Modify `Features/Reader/VoiceController.swift`.

- [ ] **Step 1: Add a cursor→ref accessor** — After `page(forCursor:)` add:

```swift
    /// The (hadith number, word-in-body) a flat cursor points at, for prose page
    /// mapping (prose pages are runtime, so PageScreen resolves the page).
    func proseRef(forCursor c: Int) -> (hadith: Int, wordInBody: Int)? {
        guard let index, !index.refs.isEmpty else { return nil }
        let r = index.refs[min(max(0, c), index.refs.count - 1)]
        return (r.bayt, r.wordIndex)
    }
```

- [ ] **Step 2: Guard `page(forCursor:)` for prose** — prose refs have `page == 0` (unknown), so auto-turn must not use it. Change `page(forCursor:)` to return nil for prose:

```swift
    func page(forCursor c: Int) -> Int? {
        guard let index, !index.refs.isEmpty else { return nil }
        let r = index.refs[min(max(0, c), index.refs.count - 1)]
        return r.page > 0 ? r.page : nil      // prose (page 0) → PageScreen maps it
    }
```

- [ ] **Step 3: Build** — `xcodebuild build ...` → BUILD SUCCEEDED. (No behaviour change for poems: their refs always have page ≥ 1.)

- [ ] **Step 4: Commit**

```bash
git add Features/Reader/VoiceController.swift
git commit -m "VoiceController: expose cursor hadith ref; page(forCursor) nil for prose"
```

---

## Task 6: `PageScreen` wiring — controls, prose start, auto-turn, mistake jump, summary text

Re-enable Memorize/mic for prose, start a prose session at the current hadith, map the cursor to a prose page for auto-turn, pass the reveal to `ProsePageView`, and label prose mistakes by hadith.

**Files:** Modify `Features/Reader/PageScreen.swift` (incl. its `SummaryCard`).

- [ ] **Step 1: Re-enable controls for prose** — The footer currently gates `if matn.kind == .poem { ModeToggle … mic }`. Change the gate to show for both poem and prose (remove the `== .poem` condition so prose gets the toggle + mic):

```swift
            HStack(spacing: 12) {
                ModeToggle(mode: $mode, tint: subjectAccent)
                    .fixedSize()
                if mode == .memorize {
                    MicButton(isListening: Binding(
                        get: { voice.isLive },
                        set: { on in on ? startVoice() : voice.stop() }
                    ), tint: subjectAccent)
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 0)
```

- [ ] **Step 2: Start a prose session at the current hadith** — `startVoice()` currently calls `voice.start(matn:fromPage:bayt:flags:)`. For prose, pass the current hadith as `bayt` (reuses the `firstWordIndex(ofBayt:)` seed). Add a helper and use it:

```swift
    /// The hadith number shown on the current page (prose), else nil.
    private var currentHadith: Int? {
        displayPages.first { $0.page == currentPage }?
            .items.compactMap { if case .hadith(let f) = $0 { return f.hadithNumber } else { return nil } }.first
    }

    private func startVoice(bayt: Int? = nil) {
        let seed = matn.kind == .prose ? currentHadith : bayt
        voice.start(matn: matn, fromPage: currentPage, bayt: seed, flags: flagStore)
    }
```

- [ ] **Step 2b: Pass the reveal into `ProsePageView`** — In `PageView` (which renders the `.hadith` case), thread the reveal through so memorize mode gets it. In `PageView.swift`, the `.hadith` arm becomes:

```swift
                            case .hadith(let fragment):
                                ProsePageView(fragment: fragment,
                                              subjectColor: matn.subject.accent,
                                              reveal: mode == .memorize ? reveal : nil)
```

(`PageView` already receives `reveal: RevealState?` and `mode` — same ones used for bayts.)

- [ ] **Step 3: Auto page-turn for prose** — The reader has an `.onChange(of: voice.cursor)` (or similar) that calls `voice.page(forCursor:)`. For prose that returns nil; map the cursor to a prose page here. Find the existing auto-turn block and extend it:

```swift
        .onChange(of: voice.cursor) { _, c in
            let target: Int?
            if matn.kind == .prose {
                target = voice.proseRef(forCursor: c).flatMap { ref in
                    prosePages.first { page in
                        page.items.contains { if case .hadith(let f) = $0 {
                            return f.hadithNumber == ref.hadith
                                && f.bodyStart <= ref.wordInBody
                                && ref.wordInBody < f.bodyStart + f.words.count
                        } else { return false } }
                    }?.page
                }
            } else {
                target = voice.page(forCursor: c)
            }
            guard let target, target != currentPage else { return }
            if reduceMotion { currentPage = target } else { withAnimation { currentPage = target } }
        }
```

(Adapt to the existing handler's exact shape — there is already a cursor→page auto-turn using `voice.page(forCursor:)`; this adds the prose branch. Keep the existing `autoTurnTarget` guard if present.)

- [ ] **Step 4: Add `wordIndex` to `Mistake`, then map the jump page for prose** — First, `ReviewSummary.Mistake` has no word index today (only `bayt`, `half`). Add `let wordIndex: Int` to the `Mistake` struct in `VoiceController.swift` and set it in BOTH `makeSummary` constructions from `ref.wordIndex` (the two `.init(...)` calls — the judged-mistakes map and the added-words map). This is harmless for poems (they already have `ref.wordIndex`). Example for the judged map:

```swift
        var mistakes = judged.filter(\.value.isMistake).keys.map { i -> ReviewSummary.Mistake in
            let ref = index.refs[i]
            var heard: String?
            if case .wrong(let said) = judged[i] { heard = said }
            return .init(id: i, page: ref.page, bayt: ref.bayt, half: ref.half,
                         wordIndex: ref.wordIndex, expected: index.displayWords[i], heard: heard)
        }
```

Then, in `PageScreen`, the `SummaryCard`'s `show(mistake)` closure jumps to `mistake.page` — for prose `page == 0`, so map it via the fragment lookup (word-in-body is `mistake.wordIndex`):

```swift
                                show: { mistake in
                                    let target: Int
                                    if matn.kind == .prose {
                                        target = prosePages.first { page in
                                            page.items.contains { if case .hadith(let f) = $0 {
                                                return f.hadithNumber == mistake.bayt
                                                    && f.bodyStart <= mistake.wordIndex
                                                    && mistake.wordIndex < f.bodyStart + f.words.count
                                            } else { return false } }
                                        }?.page ?? max(1, currentPage)
                                    } else {
                                        target = mistake.page
                                    }
                                    if reduceMotion { currentPage = target }
                                    else { withAnimation { currentPage = target } }
                                },
```

- [ ] **Step 5: Kind-aware mistake row text** — In `SummaryCard`'s `MistakeRow` (or where it formats "Bayt N · half"), branch on `matn.kind`: for prose show `"الحديث \(Numerals.eastern(mistake.bayt))"` instead of the bayt/half phrasing. Pass `matn.kind` (or a precomputed label) into the row.

- [ ] **Step 6: Build + full regression suite**

Run: `xcodegen generate && xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' 2>&1 | grep -E "✘ Test|BUILD FAILED|error:" | head`
Expected: BUILD SUCCEEDED; the only failing test is the pre-existing `everyMatnHasItsPhonemes` on bayqūniyya (unrelated — do not fix here). No poem-voice regressions (`VoiceFlowTests`, `RevealStateTests`, `RecitationIndexTests`, `TrackerAccuracyTests` all green).

- [ ] **Step 7: Commit**

```bash
git add Features/Reader/PageScreen.swift Features/Reader/PageView.swift Features/Reader/VoiceController.swift
git commit -m "Reader: prose voice — controls, start-at-hadith, auto-turn, mistake jump"
```

---

## Task 7: Device integration check

**No code (unless fixes needed).** Build + deploy to the device and recite.

- [ ] **Step 1: Deploy**

```bash
xcodebuild -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -configuration Debug \
  -destination 'platform=iOS,id=83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941' \
  -derivedDataPath ./build/DerivedData -allowProvisioningUpdates build
APP=$(find ./build/DerivedData/Build/Products -maxdepth 2 -name "HifzAlMutun.app" -path "*iphoneos*" | head -1)
xcrun devicectl device install app --device 83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941 "$APP"
xcrun devicectl device process launch --device 83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941 com.farhan.hifzalmutun
```

- [ ] **Step 2: Verify on device** (user-driven): open a hadith, switch to Memorize → the body shows blanks (underlined, invisible-ink). Tap the mic and recite → words fill in; a wrong word shows red, a skipped one dim. A long hadith auto-turns the page as you cross it. Stop → the review summary lists mistakes as "الحديث N …"; tapping one jumps to its page. Tap-to-reveal (no mic) still reveals the next word. Confirm the **poems still behave exactly as before**.

- [ ] **Step 3:** No commit (verification only). Report any issues for a follow-up task.

---

## Notes for the implementer
- **"bayt = hadith" is deliberate reuse**, documented in `RecitationIndex`. The reveal/session/summary machinery is unit-agnostic; prose uses one `.sadr` half per hadith. Do not add parallel prose index/reveal types — that was the superseded approach.
- **Poem path must stay behaviourally identical.** The only shared-code edits are additive (a prose branch in `RecitationIndex.init`, a `wordIndex` field on `Mistake`, a `page>0` guard in `page(forCursor:)`). Keep them so, and rely on the poem-voice test suites as the guard.
- **Harakat/vowel-slip is out of scope** — do not attach `VowelChecker` for prose (the `start` path only attaches it when `PhonemeIndex(matnID:index:)` is non-nil; for prose, don't build one).
- Invisible-ink colours (cream + underline; rumuz red; dim ink for skipped) are starting points — tunable on device.
