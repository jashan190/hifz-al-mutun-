# Cumulative Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the auto-pinned Session-Review card with a persistent footer "Review · N" button that opens a roomy sheet listing every flagged word for the poem (location + word), tap-to-jump+flash, swipe-to-remove, with "you said X" shown only for the most recent sitting.

**Architecture:** A pure resolver turns `Matn` + its `FlagStore` flags into sorted `ReviewItem` rows (location + the word, read from the matn content). A `ReviewSheet` presents them (reading from `FlagStore`, so it stays live). `PageScreen` gains a footer button bound to the flag count and presents the sheet; row taps reuse the existing jump + `flashTarget` path, and "you said X" is overlaid from the current `voice.summary` only. The old `SummaryCard` is removed.

**Tech Stack:** SwiftUI (iOS 26), Swift Testing, SwiftData (`FlagStore`, unchanged). Build/test sim id `0F8C82CA-6844-40E1-B260-9F1024DB07EC` (iOS 26.5; `-showdestinations` if gone; ignore the "IOSurfaceClientSetSurfaceNotify" line). Device UDID `83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941`. Run `xcodegen generate` after adding files.

**CRITICAL GIT RULE (for implementers/reviewers):** never run `git checkout`/`git switch`/`git reset` or anything that moves HEAD/branches — a prior checkout orphaned commits. Only `git add`/`git commit` on `new-mutun`, and `git show`/`git diff`/`git log`/`git status`. After committing, run `git branch --show-current` and confirm it says `new-mutun`.

**Reused facts:**
- `FlagStore` (MainActor, ObservableObject): `@Published flags: [String: Set<FlagKey>]`, `isFlagged(_ matnID:String,_ key:FlagKey)->Bool`, `setFlag(_ on:Bool, matnID:String,_ key:FlagKey)`, `count(for matnID:String)->Int`, `inMemory()`. `FlagKey(bayt:Int, half:Half, wordIndex:Int)` (Hashable). `Half { .sadr, .ajuz }`.
- `Matn`: `kind: MatnKind`, `pages: [MatnPage]` (items `.bayt(Bayt)`/`.heading`/`.hadith`), `hadiths: [Hadith]`, `baytsPerPage:Int`, `page(ofBayt bayt:Int)->Int` (guards prose), `subject`. `Bayt { number:Int; sadr:Hemistich; ajuz:Hemistich }`, `Hemistich.words: [Word]` (`Word.text`). `Hadith { number:Int; body:[ProseWord] }` (`ProseWord.text`). `Numerals.eastern(_:)`.
- `ReviewSummary { baytsRecited, revealed, mistakes:[Mistake] }`; `Mistake { id, page, bayt, half, wordIndex, expected, heard, added }` (in `VoiceController.swift`).
- `PageScreen.swift`: footer (`private var footer`) HStack = ModeToggle + (mic if memorize) + Spacer + page counter. The bottom `.safeAreaInset` currently builds `SummaryCard(...)` when `voice.summary != nil && mode == .memorize`, whose `show:` closure computes a jump `target` (prose via `prosePage(hadith:wordInBody:)`, poem via `mistake.page`), sets `currentPage`, sets `flashTarget = FlagKey(...)`, and clears it after 1.2s. `@State flashTarget: FlagKey?` exists. `prosePage(hadith:wordInBody:)->Int?` exists. `startVoice()`, `setMode(_:)`, `subjectAccent`, `chrome`, `Theme.onChrome`, `Theme.onChromeDim` exist.
- `MistakeRow` (private in PageScreen.swift) renders `expected` (an `AttributedString` with differing letters in `Theme.error` via `LetterEmphasis.ranges(written:heard:)`) and a "you said"/"skipped"/"added" line. `PageFont.font(size:)`.

---

## File map

- **Create:** `Features/Reader/ReviewItems.swift` (pure resolver + annotation map), `Features/Reader/ReviewSheet.swift` (the sheet + its `MistakeCard` row), `Tests/MatchingTests/ReviewItemsTests.swift`.
- **Modify:** `Features/Reader/PageScreen.swift` (footer button, `reviewPresented` state, `.sheet`, auto-open, `goToFlag`, remove `SummaryCard`). The old `SummaryCard`/`MistakeRow` structs are moved/retired (their rendering logic moves into `MistakeCard`).

---

## Task 1: `ReviewItems` resolver + annotation map

**Files:** Create `Features/Reader/ReviewItems.swift`; Test `Tests/MatchingTests/ReviewItemsTests.swift`.

- [ ] **Step 1: Write the failing test** — Create `Tests/MatchingTests/ReviewItemsTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct ReviewItemsTests {
    private func poemMatn() -> Matn {
        let b1 = Bayt(number: 1,
            sadr: Hemistich(text: "في النظم", segments: [], words: [Word(text:"في",normalized:"في"), Word(text:"النظم",normalized:"النظم")]),
            ajuz: Hemistich(text: "أولا", segments: [], words: [Word(text:"أولا",normalized:"اولا")]))
        let b2 = Bayt(number: 2,
            sadr: Hemistich(text: "ثم بعد", segments: [], words: [Word(text:"ثم",normalized:"ثم"), Word(text:"بعد",normalized:"بعد")]),
            ajuz: Hemistich(text: "تلا", segments: [], words: [Word(text:"تلا",normalized:"تلا")]))
        let page = MatnPage(page: 1, items: [.bayt(b1), .bayt(b2)])
        return Matn(id: "p", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "الرجز", subject: .quran, kind: .poem, hadiths: [],
                    baytsPerPage: 10, pageCount: 1, baytCount: 2, pages: [page], babs: [], reviewNotes: [])
    }
    private func proseMatn() -> Matn {
        let h1 = Hadith(number: 1, title: "الحديث الأول",
            body: [ProseWord(text:"عَنْ",normalized:"عن",role:.isnad), ProseWord(text:"إِنَّمَا",normalized:"انما",role:.matn)],
            takhrij: "")
        return Matn(id: "q", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "", subject: .hadith, kind: .prose, hadiths: [h1],
                    baytsPerPage: 0, pageCount: 0, baytCount: 1, pages: [], babs: [], reviewNotes: [])
    }

    @Test func resolvesPoemFlagsToWordAndLocationInReadingOrder() {
        let flags: Set<FlagKey> = [
            FlagKey(bayt: 2, half: .sadr, wordIndex: 1),   // "بعد"
            FlagKey(bayt: 1, half: .ajuz, wordIndex: 0),   // "أولا"
            FlagKey(bayt: 1, half: .sadr, wordIndex: 0),   // "في"
        ]
        let items = ReviewItems.resolve(matn: poemMatn(), flags: flags)
        // reading order: (1,sadr,0) (1,ajuz,0) (2,sadr,1)
        #expect(items.map(\.word) == ["في", "أولا", "بعد"])
        #expect(items[0].location == "Bayt 1 · first half")
        #expect(items[1].location == "Bayt 1 · second half")
        #expect(items[2].location == "Bayt 2 · first half")
    }

    @Test func resolvesProseFlagToHadithWord() {
        let items = ReviewItems.resolve(matn: proseMatn(),
            flags: [FlagKey(bayt: 1, half: .sadr, wordIndex: 1)])
        #expect(items.count == 1)
        #expect(items[0].word == "إِنَّمَا")
        #expect(items[0].location == "الحديث ١")
    }

    @Test func skipsOrphanOutOfRangeKeys() {
        let items = ReviewItems.resolve(matn: poemMatn(),
            flags: [FlagKey(bayt: 99, half: .sadr, wordIndex: 0),       // no such bayt
                    FlagKey(bayt: 1, half: .sadr, wordIndex: 9)])       // index out of range
        #expect(items.isEmpty)
    }

    @Test func annotationMapKeysByPosition() {
        let m = ReviewSummary.Mistake(id: 0, page: 1, bayt: 2, half: .ajuz,
                                      wordIndex: 0, expected: "تلا", heard: "تلى")
        let map = ReviewItems.annotations(ReviewSummary(baytsRecited: 1, revealed: 0, mistakes: [m]))
        #expect(map[FlagKey(bayt: 2, half: .ajuz, wordIndex: 0)]?.heard == "تلى")
    }
}
```

- [ ] **Step 2: Run it — verify it FAILS** (`ReviewItems` undefined).

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' -only-testing:HifzAlMutunTests/ReviewItemsTests`
Expected: FAIL (no `ReviewItems`). Run `xcodegen generate` first if the file isn't found.

- [ ] **Step 3: Implement** — Create `Features/Reader/ReviewItems.swift`:

```swift
import Foundation

/// One row of the cumulative review: a flagged word, where it is, and the text.
struct ReviewItem: Identifiable {
    let key: FlagKey
    let word: String        // the flagged word, as written
    let location: String    // "Bayt 12 · first half" / "الحديث ٣"
    var id: FlagKey { key }
}

/// Resolves a matn's flagged positions into display rows, and builds the
/// (ephemeral) "you said X" annotation map from a sitting's summary.
enum ReviewItems {
    /// Flagged words for a matn, in reading order. Orphan/out-of-range keys
    /// (none such for stable content) are skipped.
    static func resolve(matn: Matn, flags: Set<FlagKey>) -> [ReviewItem] {
        let sorted = flags.sorted {
            ($0.bayt, $0.half == .sadr ? 0 : 1, $0.wordIndex)
                < ($1.bayt, $1.half == .sadr ? 0 : 1, $1.wordIndex)
        }
        return sorted.compactMap { key in
            guard let word = word(matn: matn, key: key) else { return nil }
            return ReviewItem(key: key, word: word, location: location(matn: matn, key: key))
        }
    }

    private static func word(matn: Matn, key: FlagKey) -> String? {
        if matn.kind == .prose {
            guard let h = matn.hadiths.first(where: { $0.number == key.bayt }),
                  key.wordIndex >= 0, key.wordIndex < h.body.count else { return nil }
            return h.body[key.wordIndex].text
        }
        for page in matn.pages {
            for item in page.items {
                guard case .bayt(let b) = item, b.number == key.bayt else { continue }
                let hemi = key.half == .sadr ? b.sadr : b.ajuz
                guard key.wordIndex >= 0, key.wordIndex < hemi.words.count else { return nil }
                return hemi.words[key.wordIndex].text
            }
        }
        return nil
    }

    private static func location(matn: Matn, key: FlagKey) -> String {
        if matn.kind == .prose { return "الحديث \(Numerals.eastern(key.bayt))" }
        return "Bayt \(key.bayt) · \(key.half == .sadr ? "first half" : "second half")"
    }

    /// Map a finished sitting's mistakes by position, so the matching review
    /// rows can show "you said X" while the summary is in memory.
    static func annotations(_ summary: ReviewSummary) -> [FlagKey: ReviewSummary.Mistake] {
        var map: [FlagKey: ReviewSummary.Mistake] = [:]
        for m in summary.mistakes {
            let key = FlagKey(bayt: m.bayt, half: m.half, wordIndex: m.wordIndex)
            // Prefer a word's own mistake (wrong/skipped) over an "added after" one.
            if let existing = map[key], existing.added, !m.added { map[key] = m }
            else if map[key] == nil { map[key] = m }
        }
        return map
    }
}
```

- [ ] **Step 4: Run the tests — verify all 4 PASS.**

- [ ] **Step 5: Commit**

```bash
git add Features/Reader/ReviewItems.swift Tests/MatchingTests/ReviewItemsTests.swift
git commit -m "Review: resolve flagged positions to word+location rows; annotation map"
```

---

## Task 2: `MistakeCard` row

**Files:** Create part of `Features/Reader/ReviewSheet.swift` (the `MistakeCard` struct). No unit test (view) — verified by build + device.

- [ ] **Step 1: Create the row** — Create `Features/Reader/ReviewSheet.swift` with just the card for now (the sheet is Task 3):

```swift
import SwiftUI

/// One review row: location + the flagged word. When a fresh sitting's mistake
/// is supplied, it enriches the row with the differing letters marked and a
/// "you said X" / "skipped" / "added" line.
struct MistakeCard: View {
    let location: String
    let word: String
    /// The current sitting's mistake at this position, if any (ephemeral detail).
    var mistake: ReviewSummary.Mistake? = nil
    let onSelect: () -> Void

    /// The word with its differing letters (vs what was heard) in error-red.
    private var wordText: AttributedString {
        var text = AttributedString(word)
        text.foregroundColor = Theme.ink
        guard let m = mistake, let heard = m.heard, !m.added else { return text }
        let scalars = word.unicodeScalars
        for r in LetterEmphasis.ranges(written: word, heard: heard) {
            let lo = scalars.index(scalars.startIndex, offsetBy: r.lowerBound)
            let hi = scalars.index(scalars.startIndex, offsetBy: r.upperBound)
            guard let a = AttributedString.Index(lo, within: text),
                  let b = AttributedString.Index(hi, within: text) else { continue }
            text[a..<b].foregroundColor = Theme.error
        }
        return text
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(location)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(wordText)
                        .font(PageFont.font(size: 26))
                    if let m = mistake {
                        HStack(spacing: 5) {
                            Text(m.added ? "you added" : m.heard == nil ? "skipped" : "you said")
                                .font(.footnote).foregroundStyle(Theme.error)
                            if let heard = m.heard {
                                Text(heard).font(PageFont.font(size: 20)).foregroundStyle(Theme.error)
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink.opacity(0.35))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mistake.map {
            $0.added ? "\(location). After \(word), you added \($0.heard ?? "")."
                     : "\(location). Should be \(word)." + ($0.heard.map { " You said \($0)." } ?? " You skipped it.")
        } ?? "\(location). Flagged word \(word).")
        .accessibilityHint("Shows this word on the page")
    }
}
```

- [ ] **Step 2: Build** — `xcodegen generate && xcodebuild build -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' 2>&1 | grep -E "error:|BUILD SUCCEEDED" | head` → BUILD SUCCEEDED. (`LetterEmphasis`, `PageFont`, `Theme` are in-module.)

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ReviewSheet.swift
git commit -m "Review: MistakeCard row (location + word, optional you-said)"
```

---

## Task 3: `ReviewSheet`

**Files:** Modify `Features/Reader/ReviewSheet.swift` (add the sheet). No unit test (view).

- [ ] **Step 1: Add the sheet** — In `Features/Reader/ReviewSheet.swift`, add above `MistakeCard`:

```swift
/// The cumulative review for one matn: every flagged word, in reading order,
/// read live from the FlagStore. Rows for the current sitting show "you said X".
struct ReviewSheet: View {
    let matn: Matn
    /// Ephemeral annotations from the current sitting (empty when none).
    var annotations: [FlagKey: ReviewSummary.Mistake] = [:]
    let onSelect: (FlagKey) -> Void
    let onRemove: (FlagKey) -> Void
    let reviewAgain: () -> Void
    let done: () -> Void

    @EnvironmentObject private var flagStore: FlagStore

    private var items: [ReviewItem] {
        ReviewItems.resolve(matn: matn, flags: flagStore.flags[matn.id] ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("المراجعة")
                        .font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                        .environment(\.layoutDirection, .rightToLeft)
                    Text(items.isEmpty ? "No flagged words yet"
                         : "\(Numerals.eastern(items.count)) flagged \(items.count == 1 ? "word" : "words")")
                        .font(.subheadline).foregroundStyle(Theme.ink.opacity(0.7))
                }
                Spacer()
                Button { done() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.ink.opacity(0.06)))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Theme.margin).padding(.top, Theme.margin).padding(.bottom, 10)

            if items.isEmpty {
                Spacer()
                Text("Flag a word (long-press) or recite to collect your trouble spots here.")
                    .font(.subheadline).foregroundStyle(Theme.ink.opacity(0.6))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        MistakeCard(location: item.location, word: item.word,
                                    mistake: annotations[item.key]) { onSelect(item.key) }
                            .listRowInsets(EdgeInsets(top: 2, leading: Theme.margin, bottom: 2, trailing: Theme.margin))
                            .listRowSeparator(.visible)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { onRemove(item.key) } label: {
                                    Label("Remove", systemImage: "flag.slash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: reviewAgain) { Text("Review again").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .tint(matn.subject.accent)
            .padding(Theme.margin)
        }
        .background(Theme.page.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 2: Build** — BUILD SUCCEEDED. (`PressableStyle`, `Theme.page`, `Theme.margin` are in-module.)

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ReviewSheet.swift
git commit -m "Review: cumulative ReviewSheet (flagged words, swipe-to-remove)"
```

---

## Task 4: `PageScreen` — footer button, present the sheet, retire the card

**Files:** Modify `Features/Reader/PageScreen.swift`.

- [ ] **Step 1: Add state + a jump helper** — Add near the other `@State`s:

```swift
    @State private var reviewPresented = false
```

Extract the jump+flash logic (currently inline in the `SummaryCard` `show:` closure) into a method, keyed by `FlagKey`:

```swift
    /// Jump to a flagged/mistaken word and flash it.
    private func goToFlag(_ key: FlagKey) {
        let target: Int
        if matn.kind == .prose {
            target = prosePage(hadith: key.bayt, wordInBody: key.wordIndex) ?? max(1, currentPage)
        } else {
            target = min(max(1, matn.page(ofBayt: key.bayt)), max(1, displayPageCount))
        }
        if reduceMotion { currentPage = target } else { withAnimation { currentPage = target } }
        flashTarget = key
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if flashTarget == key { flashTarget = nil }
        }
    }
```

- [ ] **Step 2: Remove the old `SummaryCard` from the bottom inset** — In the `.safeAreaInset(edge: .bottom)` VStack, DELETE the entire `if let summary = voice.summary, mode == .memorize { SummaryCard(...) … }` block (keep `if barsVisible { footer }`). Then delete the now-unused `SummaryCard` and `MistakeRow` private structs from `PageScreen.swift` (their rendering moved to `MistakeCard`). If `stat(_:_:)` or other helpers were only used by `SummaryCard`, delete them too; if the compiler flags any still-referenced symbol, keep it.

- [ ] **Step 3: Add the footer "Review · N" button** — In `private var footer`, inside the `HStack`, add the button after the mic (before `Spacer`). It shows the flag count and opens the sheet:

```swift
                if mode == .memorize {
                    MicButton(...)   // existing
                }
                Button { reviewPresented = true } label: {
                    let n = flagStore.count(for: matn.id)
                    HStack(spacing: 5) {
                        Image(systemName: "flag.fill").font(.system(size: 12, weight: .semibold))
                        Text(n > 0 ? "مراجعة · \(Numerals.eastern(n))" : "مراجعة")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(n > 0 ? Theme.onChrome : Theme.onChromeDim)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.onChrome.opacity(0.12)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
                Spacer(minLength: 0)
                // … the existing page-counter `Text(currentPage >= 1 ? "\(…) / \(…)" : "الغلاف")`
                // stays exactly as it is — insert the Review button ABOVE this, after the mic.
```

(`flagStore` is already an `@EnvironmentObject`/property on `PageScreen` — confirm by how the reader reads it today; the count re-reads reactively because `FlagStore` is `@Published`.)

- [ ] **Step 4: Present the sheet + auto-open after a sitting** — Add the `.sheet` and the auto-open onChange to the reader body (e.g. alongside the other modifiers on the `GeometryReader`/root). Inject the environment object explicitly to be safe:

```swift
        .sheet(isPresented: $reviewPresented) {
            ReviewSheet(
                matn: matn,
                annotations: voice.summary.map { ReviewItems.annotations($0) } ?? [:],
                onSelect: { key in reviewPresented = false; goToFlag(key) },
                onRemove: { key in flagStore.setFlag(false, matnID: matn.id, key) },
                reviewAgain: { reviewPresented = false; startVoice() },
                done: { reviewPresented = false })
            .environmentObject(flagStore)
        }
        .onChange(of: voice.summary != nil) { _, hasSummary in
            if hasSummary { reviewPresented = true }   // auto-open once a sitting ends
        }
```

- [ ] **Step 5: Build + full regression suite**

Run: `xcodegen generate && xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' 2>&1 | grep -E "✘ Test|BUILD FAILED|error:" | head`
Expected: BUILD SUCCEEDED; ReviewItemsTests pass; the ONLY failing test is the pre-existing `everyMatnHasItsPhonemes` (bayqūniyya). No poem/voice regressions. Fix any compile fallout from deleting `SummaryCard`/`MistakeRow` (e.g. an orphan `show:`/`backToRead` reference).

- [ ] **Step 6: Commit**

```bash
git add Features/Reader/PageScreen.swift
git commit -m "Reader: footer Review·N button + cumulative review sheet; retire pinned card"
```

---

## Task 5: Device check

**No code (unless fixes needed).** Build + deploy and verify.

- [ ] **Step 1: Deploy** (the standard device build/install/launch block).

- [ ] **Step 2: Verify:** the footer shows "مراجعة · N" at all times (read + memorize), N = flagged count; tapping opens a full-height sheet listing every flagged word (location + word) in reading order; tapping a row closes the sheet and jumps+flashes that word; swipe a row → Remove clears the flag (and its page box); recite a hadith/poem → on stop the sheet auto-opens and the just-made mistakes show "you said X"; reopening later shows them without the "you said" line. Confirm the old pinned card is gone and poems/voice otherwise behave as before.

- [ ] **Step 3:** No commit (verification only). Report issues.

---

## Notes for the implementer
- The sheet reads `flagStore` live, so Remove updates the list immediately; `reviewPresented` state drives presentation.
- `goToFlag` clamps the poem page to `displayPageCount` (guards the ORPHAN-folded last page where `matn.page(ofBayt:)` could overshoot).
- "you said X" comes only from the current `voice.summary`; once it's nil (next sitting / cleared), rows show location+word only — by design.
- Do NOT change how flags are created (voice `syncFlags` / manual long-press) or the box+flash rendering.
