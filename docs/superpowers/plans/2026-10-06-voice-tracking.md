# Voice Tracking (Memorize mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user recite a matn aloud in Memorize mode and have the app reveal the poem word-by-word as each word is correctly recited, following along even when the speech recognizer mishears chanted Arabic.

**Architecture:** The recognizer's output is treated as a noisy hint. A pure-logic `RecitationTracker` walks a cursor forward through the matn's known normalized words, advancing on fuzzy matches within a small forward window; the UI reveals words up to the cursor. The speech engine (Apple's iOS 26 `SpeechAnalyzer`) sits behind a `SpeechSource` protocol so it is swappable and so the tracker/reveal logic can be fully unit-tested without audio.

**Tech Stack:** Swift 5, SwiftUI, iOS 26, Speech framework (`SpeechAnalyzer`/`SpeechTranscriber`), AVFoundation, Swift Testing, XcodeGen.

**Design spec:** `docs/superpowers/specs/2026-10-06-voice-tracking-design.md`

---

## Conventions used throughout this plan

**Regenerate the Xcode project** (after any `project.yml` edit):

```bash
cd "/Users/farhan/Developer/hifz-al-mutun-" && xcodegen generate
```

**Build the app:**

```bash
xcodebuild build -scheme HifzAlMutun \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -quiet
```

**Run the unit tests** (whole suite):

```bash
xcodebuild test -scheme HifzAlMutun \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -quiet
```

**Run one test** (Swift Testing, by suite/function name):

```bash
xcodebuild test -scheme HifzAlMutun \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HifzAlMutunTests/<SuiteName>/<testFunc> -quiet
```

The app targets iOS 26, so the destination must be a simulator on the **iOS 26.x runtime** (the iPhone 16 family here is only iOS 18.6; the iPhone 17 family is iOS 26.5). If `iPhone 17` is unavailable or its name is ambiguous, run `xcrun simctl list devices available | grep -B1 -A20 "iOS 26"` and use a unique device name or a device id (`id=<UUID>`).

**File layout created by this plan:**
- `Core/Matching/ArabicNormalize.swift` — runtime port of `Tools/normalize.py`
- `Core/Matching/Levenshtein.swift` — edit distance (fuzzy matching)
- `Core/Matching/RecitationIndex.swift` — flattens a `Matn` into an ordered word list + back-references
- `Core/Matching/RecitationTracker.swift` — the cursor/matching brain
- `Core/Matching/HemistichReveal.swift` — word → segment-range slicing for the reveal
- `Core/Speech/SpeechSource.swift` — protocol + `TranscriptFragment` + `MockSpeechSource`
- `Core/Speech/AppleSpeechSource.swift` — live mic → `SpeechAnalyzer`
- `Core/Speech/FileSpeechSource.swift` — audio file → `SpeechAnalyzer` (spike + fixtures)
- `Features/Reader/RecitationSession.swift` — ties source → tracker → published reveal state
- `Tests/MatchingTests/*` — unit tests for all pure logic
- `Tests/SpeechTests/*` — file-transcription spike + fixture accuracy

---

## Task 1: Project config — iOS 26, test target, permissions

**Files:**
- Modify: `project.yml`
- Modify: `README.md:3` (iOS 18+ → iOS 26+)
- Create: `Tests/MatchingTests/PlaceholderTest.swift` (temporary, deleted in Task 2)

- [ ] **Step 1: Raise the deployment target**

In `project.yml`, change the `deploymentTarget` block:

```yaml
  deploymentTarget:
    iOS: "26.0"
```

- [ ] **Step 2: Add the unit-test target and an explicit scheme**

In `project.yml`, under `targets:` (after the `HifzAlMutun:` target block), add:

```yaml
  HifzAlMutunTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: HifzAlMutun
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.farhan.hifzalmutun.tests
        GENERATE_INFOPLIST_FILE: YES
```

Then add a top-level `schemes:` block at the end of `project.yml` so tests run under the `HifzAlMutun` scheme:

```yaml
schemes:
  HifzAlMutun:
    build:
      targets:
        HifzAlMutun: all
        HifzAlMutunTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - HifzAlMutunTests
```

- [ ] **Step 3: Add microphone + speech-recognition usage strings**

In `project.yml`, inside the `HifzAlMutun` target's `settings.base`, add two Info.plist keys:

```yaml
        INFOPLIST_KEY_NSMicrophoneUsageDescription: "Used to listen as you recite, so the app can follow along and reveal the text."
        INFOPLIST_KEY_NSSpeechRecognitionUsageDescription: "Used to recognise your recitation on-device so the app can track your place in the poem."
```

- [ ] **Step 4: Add a temporary placeholder test** (so the test target compiles before Task 2 adds real tests)

Create `Tests/MatchingTests/PlaceholderTest.swift`:

```swift
import Testing

@Suite struct PlaceholderTests {
    @Test func placeholder() {
        #expect(1 + 1 == 2)
    }
}
```

- [ ] **Step 5: Regenerate and build**

Run:

```bash
cd "/Users/farhan/Developer/hifz-al-mutun-" && xcodegen generate
```

Expected: `Created project at .../HifzAlMutun.xcodeproj`.

- [ ] **Step 6: Run the test target to confirm wiring**

Run the whole-suite test command. Expected: build succeeds and `PlaceholderTests.placeholder` passes. If the scheme can't find the test target, re-check the `schemes:` block indentation in `project.yml` and regenerate.

- [ ] **Step 7: Update the README minimum-OS line**

In `README.md:3`, change `(SwiftUI, SwiftData, iOS 18+)` to `(SwiftUI, SwiftData, iOS 26+)`.

- [ ] **Step 8: Commit**

```bash
git add project.yml README.md Tests/MatchingTests/PlaceholderTest.swift
git commit -m "chore: iOS 26 target, unit-test target, speech/mic permissions"
```

---

## Task 2: Arabic normalizer (runtime port of normalize.py)

The tracker must normalize recognizer output with the **same** rules the content pipeline used, so it lines up with the stored `Word.normalized`. See `Tools/normalize.py` for the reference rules.

**Files:**
- Create: `Core/Matching/ArabicNormalize.swift`
- Create: `Tests/MatchingTests/ArabicNormalizeTests.swift`
- Delete: `Tests/MatchingTests/PlaceholderTest.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MatchingTests/ArabicNormalizeTests.swift` (samples copied from `normalize.py`'s self-check):

```swift
import Testing
@testable import HifzAlMutun

@Suite struct ArabicNormalizeTests {
    @Test func stripsHarakat() {
        #expect(ArabicNormalize.normalize("يَقُولُ") == "يقول")
    }
    @Test func foldsHamzaAlef() {
        #expect(ArabicNormalize.normalize("الْأَطْفَالِ") == "الاطفال")
        #expect(ArabicNormalize.normalize("آمَنُوا") == "امنوا")
    }
    @Test func foldsTaMarbutaAndAlefMaqsura() {
        #expect(ArabicNormalize.normalize("رَحْمَةِ") == "رحمه")
        #expect(ArabicNormalize.normalize("عَلَى") == "علي")
    }
    @Test func dropsPunctuationAndTatweel() {
        #expect(ArabicNormalize.normalize("(تُحْفَةِ") == "تحفه")
        #expect(ArabicNormalize.normalize("بِـ:") == "ب")
    }
    @Test func emptyForPunctuationOnly() {
        #expect(ArabicNormalize.normalize("،") == "")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:HifzAlMutunTests/ArabicNormalizeTests`
Expected: FAIL — `cannot find 'ArabicNormalize' in scope`.

- [ ] **Step 3: Implement the normalizer**

Create `Core/Matching/ArabicNormalize.swift`:

```swift
import Foundation

/// Runtime port of `Tools/normalize.py`. Produces the match-only form used to
/// line recognizer output up with the stored `Word.normalized`. Keep in sync
/// with the Python rules: strip marks + tatweel, fold أإآٱ→ا, ى→ي, ة→ه, then
/// keep only Arabic letters (U+0621–063A, U+0641–064A).
enum ArabicNormalize {
    private static func isMark(_ v: UInt32) -> Bool {
        (0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v) ||
        v == 0x0670 || (0x06D6...0x06DC).contains(v) ||
        (0x06DF...0x06E8).contains(v) || (0x06EA...0x06ED).contains(v) ||
        (0x0653...0x0655).contains(v)   // maddah / hamza above+below (from NFKD)
    }
    private static func isKeptLetter(_ v: UInt32) -> Bool {
        (0x0621...0x063A).contains(v) || (0x0641...0x064A).contains(v)
    }
    private static func fold(_ s: Unicode.Scalar) -> Unicode.Scalar {
        switch s.value {
        case 0x0623, 0x0625, 0x0622, 0x0671: return Unicode.Scalar(0x0627)! // أإآٱ → ا
        case 0x0649: return Unicode.Scalar(0x064A)!                          // ى → ي
        case 0x0629: return Unicode.Scalar(0x0647)!                          // ة → ه
        default: return s
        }
    }

    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        // Compatibility decomposition so composed forms split predictably.
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            if isMark(scalar.value) { continue }
            if scalar.value == 0x0640 { continue }   // tatweel
            let folded = fold(scalar)
            if isKeptLetter(folded.value) { out.append(folded) }
        }
        return String(out)
    }
}
```

- [ ] **Step 4: Delete the placeholder test**

```bash
rm Tests/MatchingTests/PlaceholderTest.swift
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `-only-testing:HifzAlMutunTests/ArabicNormalizeTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Core/Matching/ArabicNormalize.swift Tests/MatchingTests/ArabicNormalizeTests.swift
git rm --cached Tests/MatchingTests/PlaceholderTest.swift 2>/dev/null; true
git add -A Tests/MatchingTests/
git commit -m "feat: runtime Arabic normalizer matching the content pipeline"
```

---

## Task 3: Levenshtein edit distance

Used for fuzzy word matching (recognizer near-misses).

**Files:**
- Create: `Core/Matching/Levenshtein.swift`
- Create: `Tests/MatchingTests/LevenshteinTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MatchingTests/LevenshteinTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct LevenshteinTests {
    @Test func identicalIsZero() { #expect(levenshtein("يقول", "يقول") == 0) }
    @Test func oneSubstitution() { #expect(levenshtein("يقول", "يقيل") == 1) }
    @Test func oneInsertion() { #expect(levenshtein("قول", "يقول") == 1) }
    @Test func emptyVsWord() { #expect(levenshtein("", "يقول") == 4) }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:HifzAlMutunTests/LevenshteinTests`
Expected: FAIL — `cannot find 'levenshtein' in scope`.

- [ ] **Step 3: Implement**

Create `Core/Matching/Levenshtein.swift`:

```swift
import Foundation

/// Classic two-row Levenshtein distance over Characters.
func levenshtein(_ a: String, _ b: String) -> Int {
    let s = Array(a), t = Array(b)
    if s.isEmpty { return t.count }
    if t.isEmpty { return s.count }
    var prev = Array(0...t.count)
    var curr = [Int](repeating: 0, count: t.count + 1)
    for i in 1...s.count {
        curr[0] = i
        for j in 1...t.count {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[t.count]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `-only-testing:HifzAlMutunTests/LevenshteinTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Matching/Levenshtein.swift Tests/MatchingTests/LevenshteinTests.swift
git commit -m "feat: levenshtein distance for fuzzy word matching"
```

---

## Task 4: RecitationIndex — flatten a Matn into an ordered word list

The tracker works on one flat array of normalized words in recitation order. The index also lets the UI map a cursor position back to a (bayt, half, word) location.

**Recitation order:** pages in order → items in print order → for each bayt, **sadr words then ajuz words** → words in list order.

**Files:**
- Create: `Core/Matching/RecitationIndex.swift`
- Create: `Tests/MatchingTests/RecitationIndexTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MatchingTests/RecitationIndexTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct RecitationIndexTests {
    // Build a tiny 1-page, 1-bayt matn inline.
    private func makeMatn() -> Matn {
        func hemi(_ words: [String]) -> Hemistich {
            Hemistich(
                text: words.joined(separator: " "),
                segments: [Segment(text: words.joined(separator: " "), color: .black, footnote: nil)],
                words: words.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) }
            )
        }
        let bayt = Bayt(number: 1, sadr: hemi(["يقول", "راجي"]), ajuz: hemi(["عفو", "رب"]))
        let page = MatnPage(page: 1, items: [.bayt(bayt)])
        return Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
                    pages: [page], babs: [], reviewNotes: [])
    }

    @Test func flattensSadrThenAjuz() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.normalizedWords == ["يقول", "راجي", "عفو", "رب"])
    }

    @Test func refsPointBackToLocation() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.refs[0].bayt == 1)
        #expect(idx.refs[0].half == .sadr)
        #expect(idx.refs[0].wordIndex == 0)
        #expect(idx.refs[2].half == .ajuz)
        #expect(idx.refs[2].wordIndex == 0)
    }

    @Test func firstWordIndexOnPage() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.firstWordIndex(onPage: 1) == 0)
        #expect(idx.firstWordIndex(onPage: 99) == idx.normalizedWords.count) // past the end
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:HifzAlMutunTests/RecitationIndexTests`
Expected: FAIL — `cannot find 'RecitationIndex' in scope`.

- [ ] **Step 3: Implement**

Create `Core/Matching/RecitationIndex.swift`:

```swift
import Foundation

/// Which half-line a word sits in.
enum Half: Hashable { case sadr, ajuz }

/// A back-reference from a flat word position to its place in the matn.
struct WordRef: Hashable {
    let page: Int
    let bayt: Int
    let half: Half
    let wordIndex: Int   // 0-based index within that hemistich's `words`
}

/// Flattens a `Matn` into one ordered list of normalized words (recitation
/// order: sadr then ajuz within each bayt) plus a parallel list of back-refs.
struct RecitationIndex {
    let normalizedWords: [String]
    let refs: [WordRef]
    private let pageStart: [Int: Int]   // page number → first flat word index

    init(matn: Matn) {
        var words: [String] = []
        var refs: [WordRef] = []
        var pageStart: [Int: Int] = [:]
        for page in matn.pages {
            pageStart[page.page] = words.count
            for item in page.items {
                guard case .bayt(let bayt) = item else { continue }
                for (half, hemi) in [(Half.sadr, bayt.sadr), (Half.ajuz, bayt.ajuz)] {
                    for (wi, word) in hemi.words.enumerated() {
                        words.append(word.normalized)
                        refs.append(WordRef(page: page.page, bayt: bayt.number,
                                            half: half, wordIndex: wi))
                    }
                }
            }
        }
        self.normalizedWords = words
        self.refs = refs
        self.pageStart = pageStart
    }

    /// Flat index of the first word on a page; `normalizedWords.count` if the
    /// page has no words at or after it (clamps callers to the end).
    func firstWordIndex(onPage page: Int) -> Int {
        if let start = pageStart[page] { return start }
        // Page not found (e.g. out of range): clamp to end.
        return normalizedWords.count
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `-only-testing:HifzAlMutunTests/RecitationIndexTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Matching/RecitationIndex.swift Tests/MatchingTests/RecitationIndexTests.swift
git commit -m "feat: RecitationIndex flattens a matn into an ordered word list"
```

---

## Task 5: RecitationTracker — the cursor/matching brain

Pure logic. Consumes recognized text fragments (already-noisy hints) and advances a forward-only cursor through the known words.

**Behavior contract:**
- `cursor` = number of confirmed words; the UI reveals words `[0, cursor)`.
- Forward-only within a lock: a single fragment never moves the cursor back.
- Skip tolerance: when locked, a token may match up to `maxSkip` words ahead (covers a dropped word); when `lost`, the search widens to `window` (re-sync).
- Empty-normalized expected words are transparent: the cursor auto-advances over them.
- Lock states: `idle` → `locked` (on first progress) → `lost` (locked, then no progress for `lostAfter`) → `locked` (re-sync).

**Files:**
- Create: `Core/Matching/RecitationTracker.swift`
- Create: `Tests/MatchingTests/RecitationTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MatchingTests/RecitationTrackerTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct RecitationTrackerTests {
    // Words are already normalized here for directness.
    private let words = ["يقول", "راجي", "عفو", "رب", "قادر", "محمد"]

    private func tracker() -> RecitationTracker {
        RecitationTracker(words: words, startIndex: 0,
                          window: 6, maxSkip: 3, lostAfter: 2.0)
    }

    @Test func perfectRecitationAdvancesWordByWord() {
        let t = tracker()
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        #expect(t.cursor == 1)
        #expect(t.lockState == .locked)
        t.consume(.init(text: "راجي", isFinal: true), at: 1)
        #expect(t.cursor == 2)
    }

    @Test func growingPartialsDoNotDoubleCount() {
        let t = tracker()
        t.consume(.init(text: "يقول", isFinal: false), at: 0)
        t.consume(.init(text: "يقول راجي", isFinal: false), at: 1)
        #expect(t.cursor == 2)   // not 3 — the repeated "يقول" is ignored
    }

    @Test func droppedWordIsSkipped() {
        let t = tracker()
        // Reciter says يقول … (راجي swallowed) … عفو
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        t.consume(.init(text: "عفو", isFinal: true), at: 1)
        #expect(t.cursor == 3)   // jumped over راجي
    }

    @Test func mishearToleratedByEditDistance() {
        let t = tracker()
        t.consume(.init(text: "يقيل", isFinal: true), at: 0)  // 1 substitution
        #expect(t.cursor == 1)
    }

    @Test func pauseGoesLostThenResyncs() {
        let t = tracker()
        t.consume(.init(text: "يقول راجي", isFinal: true), at: 0)
        #expect(t.cursor == 2)
        // Long silence, then an unmatched fragment: goes lost.
        t.consume(.init(text: "شيء غريب", isFinal: true), at: 5)
        #expect(t.lockState == .lost)
        // Reciter resumes further ahead; wide window re-locks.
        t.consume(.init(text: "محمد", isFinal: true), at: 6)
        #expect(t.cursor == 6)
        #expect(t.lockState == .locked)
    }

    @Test func resetMovesCursor() {
        let t = tracker()
        t.consume(.init(text: "يقول راجي", isFinal: true), at: 0)
        t.reset(to: 0)
        #expect(t.cursor == 0)
        #expect(t.lockState == .idle)
    }

    @Test func autoAdvancesOverEmptyExpectedWords() {
        let t = RecitationTracker(words: ["يقول", "", "راجي"], startIndex: 0,
                                  window: 6, maxSkip: 3, lostAfter: 2.0)
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        #expect(t.cursor == 2)   // skipped the empty slot, sits before راجي
        t.consume(.init(text: "راجي", isFinal: true), at: 1)
        #expect(t.cursor == 3)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:HifzAlMutunTests/RecitationTrackerTests`
Expected: FAIL — `cannot find 'RecitationTracker' in scope`.

- [ ] **Step 3: Implement**

Create `Core/Matching/RecitationTracker.swift`:

```swift
import Foundation

/// One recognized hint from a `SpeechSource`. `text` is the recognizer's latest
/// hypothesis (raw, un-normalized); `isFinal` marks a stabilized segment.
struct TranscriptFragment {
    let text: String
    let isFinal: Bool
}

enum LockState { case idle, locked, lost }

/// Walks a cursor forward through a known word sequence, advancing on fuzzy
/// matches of recognizer hints. Pure logic — no audio, no UI, fully testable.
final class RecitationTracker {
    let words: [String]            // expected words, already normalized
    private(set) var cursor: Int   // confirmed word count; reveal [0, cursor)
    private(set) var lockState: LockState = .idle
    private var lastProgress: TimeInterval = 0

    private let window: Int        // re-sync look-ahead when lost
    private let maxSkip: Int       // forward skip tolerance when locked
    private let lostAfter: TimeInterval

    init(words: [String], startIndex: Int = 0,
         window: Int = 12, maxSkip: Int = 3, lostAfter: TimeInterval = 2.0) {
        self.words = words
        self.cursor = min(max(0, startIndex), words.count)
        self.window = window
        self.maxSkip = maxSkip
        self.lostAfter = lostAfter
        skipEmpties(from: &cursor)
    }

    func reset(to index: Int) {
        cursor = min(max(0, index), words.count)
        skipEmpties(from: &cursor)
        lockState = .idle
        lastProgress = 0
    }

    func consume(_ fragment: TranscriptFragment, at time: TimeInterval) {
        let tokens = ArabicNormalize.normalize(fragment.text)
            .split(separator: " ").map(String.init)
        var p = cursor
        let lookahead = (lockState == .lost) ? window : (maxSkip + 1)
        for token in tokens where !token.isEmpty {
            let end = min(words.count, p + lookahead)
            if let hit = matchIndex(token, in: p..<end) {
                p = hit + 1
                skipEmpties(from: &p)
            }
        }
        if p > cursor {
            cursor = p
            lastProgress = time
            lockState = .locked
        } else if lockState == .locked, time - lastProgress > lostAfter {
            lockState = .lost
        }
    }

    // MARK: - Matching helpers

    private func matchIndex(_ token: String, in range: Range<Int>) -> Int? {
        for i in range where !words[i].isEmpty {
            if fuzzyEqual(token, words[i]) { return i }
        }
        return nil
    }

    private func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let threshold = max(1, min(a.count, b.count) / 4)
        return levenshtein(a, b) <= threshold
    }

    private func skipEmpties(from i: inout Int) {
        while i < words.count && words[i].isEmpty { i += 1 }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `-only-testing:HifzAlMutunTests/RecitationTrackerTests`
Expected: PASS (7 tests). If `pauseGoesLostThenResyncs` fails at the re-sync step, confirm `window` (6 in the test) is wide enough to reach index 5 from the cursor.

- [ ] **Step 5: Commit**

```bash
git add Core/Matching/RecitationTracker.swift Tests/MatchingTests/RecitationTrackerTests.swift
git commit -m "feat: RecitationTracker cursor + fuzzy forward matching with re-sync"
```

---

## Task 6: HemistichReveal — slice segments at a word boundary

To reveal "the first k words" of a hemistich we need the subset of its coloured `segments` covering those words — splitting a segment that spans the boundary (segments can span multiple words). Works on **unicode scalars** so a cut never lands inside a grapheme.

**Files:**
- Create: `Core/Matching/HemistichReveal.swift`
- Create: `Tests/MatchingTests/HemistichRevealTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MatchingTests/HemistichRevealTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct HemistichRevealTests {
    // "في النظم أولا" is ONE segment spanning three words — the hard case.
    private func hemi() -> Hemistich {
        let words = ["في", "النظم", "أولا"]
        return Hemistich(
            text: words.joined(separator: " "),
            segments: [Segment(text: "في النظم أولا", color: .black, footnote: nil)],
            words: words.map { Word(text: $0, normalized: $0) }
        )
    }

    @Test func zeroWordsRevealsNothing() {
        #expect(HemistichReveal.prefix(hemi(), words: 0).isEmpty)
    }
    @Test func allWordsRevealsEverything() {
        let out = HemistichReveal.prefix(hemi(), words: 3)
        #expect(out.map { $0.text ?? "" }.joined() == "في النظم أولا")
    }
    @Test func splitsSpanningSegmentAtBoundary() {
        // Reveal first word only → "في"
        let out = HemistichReveal.prefix(hemi(), words: 1)
        #expect(out.map { $0.text ?? "" }.joined() == "في")
        #expect(out.first?.color == .black)
    }
    @Test func revealsAcrossTwoColouredSegments() {
        let words = ["بدأت", "بسم", "الله"]
        let h = Hemistich(
            text: "بدأت بسم الله",
            segments: [
                Segment(text: "بدأت ", color: .red, footnote: nil),
                Segment(text: "بسم الله", color: .black, footnote: nil),
            ],
            words: words.map { Word(text: $0, normalized: $0) }
        )
        let out = HemistichReveal.prefix(h, words: 2)   // "بدأت بسم"
        #expect(out.map { $0.text ?? "" }.joined() == "بدأت بسم")
        #expect(out.first?.color == .red)
        #expect(out.last?.color == .black)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:HifzAlMutunTests/HemistichRevealTests`
Expected: FAIL — `cannot find 'HemistichReveal' in scope`.

- [ ] **Step 3: Implement**

Create `Core/Matching/HemistichReveal.swift`:

```swift
import Foundation

/// Slices a hemistich's display `segments` to just the first `k` words, so the
/// Memorize reveal can show recited words with their real colours and leave the
/// rest blank. Operates on unicode scalars so a cut never splits a grapheme.
///
/// Relies on the content invariant that a hemistich's `segments` text (text
/// runs only) concatenates exactly to its `text`, and `text` is its `words`
/// joined by single spaces.
enum HemistichReveal {
    static func prefix(_ hemistich: Hemistich, words k: Int) -> [Segment] {
        if k <= 0 { return [] }
        if k >= hemistich.words.count { return hemistich.segments }

        // Scalar length of the first k words joined by single spaces.
        let revealedPlain = hemistich.words.prefix(k).map(\.text).joined(separator: " ")
        let cut = revealedPlain.unicodeScalars.count

        var result: [Segment] = []
        var consumed = 0
        for seg in hemistich.segments {
            guard let text = seg.text else {
                // Footnote marker: keep it only if it sits within the revealed span.
                if consumed < cut { result.append(seg) }
                continue
            }
            let len = text.unicodeScalars.count
            if consumed + len <= cut {
                result.append(seg)
                consumed += len
            } else if consumed < cut {
                let take = cut - consumed
                let piece = String(String.UnicodeScalarView(text.unicodeScalars.prefix(take)))
                result.append(Segment(text: piece, color: seg.color, footnote: nil))
                break
            } else {
                break
            }
        }
        return result
    }
}
```

> **Note:** `Segment` and `Word` are declared `Decodable` structs in `Core/Models/Matn.swift` with memberwise access. If the memberwise initializer is not accessible from these files (it will be, same module), no change is needed. The tests construct them directly, confirming access.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `-only-testing:HifzAlMutunTests/HemistichRevealTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Core/Matching/HemistichReveal.swift Tests/MatchingTests/HemistichRevealTests.swift
git commit -m "feat: HemistichReveal slices coloured segments at a word boundary"
```

---

## Task 7: SpeechSource protocol + mock

The seam between audio and logic. The engine is hidden behind this so the tracker never depends on the Speech framework.

**Files:**
- Create: `Core/Speech/SpeechSource.swift`
- Create: `Tests/SpeechTests/MockSpeechSourceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SpeechTests/MockSpeechSourceTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct MockSpeechSourceTests {
    @Test func emitsScriptedFragments() async {
        let mock = MockSpeechSource(script: [
            .init(text: "يقول", isFinal: false),
            .init(text: "يقول راجي", isFinal: true),
        ])
        var got: [String] = []
        try? await mock.start()
        for await f in mock.fragments { got.append(f.text) }
        #expect(got == ["يقول", "يقول راجي"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:HifzAlMutunTests/MockSpeechSourceTests`
Expected: FAIL — `cannot find 'MockSpeechSource' in scope`.

- [ ] **Step 3: Implement the protocol + mock**

Create `Core/Speech/SpeechSource.swift`:

```swift
import Foundation

/// Produces a stream of recognized text fragments. The engine (Apple, file,
/// mock) is hidden behind this so the tracker/UI never import Speech directly.
protocol SpeechSource: AnyObject {
    /// An async stream of recognized fragments, oldest first.
    var fragments: AsyncStream<TranscriptFragment> { get }
    /// Begin producing. Throws if permission/engine setup fails.
    func start() async throws
    /// Stop producing and finish the stream.
    func stop()
}

/// A scripted source for tests: replays a fixed list of fragments.
final class MockSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let script: [TranscriptFragment]

    init(script: [TranscriptFragment]) {
        self.script = script
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        for fragment in script { continuation.yield(fragment) }
        continuation.finish()
    }

    func stop() { continuation.finish() }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `-only-testing:HifzAlMutunTests/MockSpeechSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Speech/SpeechSource.swift Tests/SpeechTests/MockSpeechSourceTests.swift
git commit -m "feat: SpeechSource protocol + scripted mock source"
```

---

## Task 8: GATE — prove Apple's on-device Arabic transcription works

This is the go/no-go spike from the spec. We transcribe a short bundled Shatibiyyah recitation clip through iOS 26's `SpeechAnalyzer` and confirm recognizable Arabic words come out. If Arabic assets won't install or stream on-device, **stop and revisit the engine choice** (WhisperKit) before proceeding — the tracker/reveal work from Tasks 2–7 is engine-independent and still stands.

**Files:**
- Create: `Core/Speech/FileSpeechSource.swift`
- Create: `Tests/SpeechTests/Fixtures/` (short audio clip)
- Create: `Tests/SpeechTests/FileTranscriptionSpikeTests.swift`
- Modify: `project.yml` (bundle the fixtures into the test target)

- [ ] **Step 1: Obtain a short recitation clip**

Fetch ~20–30s of a Shatibiyyah recitation and trim it. Example (requires `brew install yt-dlp ffmpeg`):

```bash
cd "/Users/farhan/Developer/hifz-al-mutun-"
mkdir -p Tests/SpeechTests/Fixtures
yt-dlp -x --audio-format m4a -o /tmp/shatibi_full.m4a "<YOUTUBE_URL>"
ffmpeg -y -i /tmp/shatibi_full.m4a -ss 0 -t 25 -ac 1 -ar 16000 \
  Tests/SpeechTests/Fixtures/shatibiyya_clip.m4a
```

Pick a URL of a clear recitation of the opening lines. **Fallback** if no good source: record yourself reciting the first two bayts into Voice Memos, export as `.m4a`, and drop it in as `Tests/SpeechTests/Fixtures/shatibiyya_clip.m4a`. Note the first few words you expect for Step 4's assertion.

- [ ] **Step 2: Bundle the fixtures into the test target**

In `project.yml`, add a resources path to the `HifzAlMutunTests` target so the clip is in the test bundle:

```yaml
  HifzAlMutunTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
      - path: Tests/SpeechTests/Fixtures
        buildPhase: resources
    dependencies:
      - target: HifzAlMutun
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.farhan.hifzalmutun.tests
        GENERATE_INFOPLIST_FILE: YES
```

Regenerate: `xcodegen generate`.

- [ ] **Step 3: Implement the file source**

Create `Core/Speech/FileSpeechSource.swift`:

```swift
import Foundation
import AVFoundation
import Speech

/// Transcribes an audio file through iOS 26's SpeechAnalyzer and emits the
/// recognizer's fragments. Used for the engine spike and fixture accuracy
/// tests, and as the simulator-friendly dev loop (no live mic needed).
///
/// NOTE: Exact SpeechAnalyzer/SpeechTranscriber signatures are pinned during
/// this task against Xcode 26's SDK — adjust the three marked lines if the
/// compiler disagrees; the surrounding structure is stable.
@available(iOS 26, *)
final class FileSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let url: URL
    private let locale: Locale
    private var task: Task<Void, Never>?

    init(url: URL, locale: Locale = Locale(identifier: "ar")) {
        self.url = url
        self.locale = locale
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        task = Task { [continuation, url, locale] in
            do {
                let transcriber = SpeechTranscriber(            // (1) init form
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults],
                    attributeOptions: []
                )
                try await Self.ensureModel(for: transcriber, locale: locale)

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let file = try AVAudioFile(forReading: url)

                // Stream results as they arrive.
                let reader = Task {
                    for try await result in transcriber.results {  // (2) results seq
                        let text = String(result.text.characters)
                        continuation.yield(.init(text: text, isFinal: result.isFinal))
                    }
                }

                if let last = try await analyzer.analyzeSequence(from: file) { // (3) file input
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
                reader.cancel()
                continuation.finish()
            } catch {
                continuation.finish()
            }
        }
    }

    func stop() {
        task?.cancel()
        continuation.finish()
    }

    /// Ensure the on-device model for this locale is installed.
    private static func ensureModel(for transcriber: SpeechTranscriber,
                                    locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else { throw SpeechSourceError.localeUnsupported }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

enum SpeechSourceError: Error { case localeUnsupported }
```

- [ ] **Step 4: Write the spike test**

Create `Tests/SpeechTests/FileTranscriptionSpikeTests.swift`:

```swift
import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct FileTranscriptionSpikeTests {
    @available(iOS 26, *)
    @Test func transcribesArabicClip() async throws {
        let url = try #require(
            Bundle(for: SpikeAnchor.self).url(forResource: "shatibiyya_clip", withExtension: "m4a"),
            "fixture clip missing from test bundle")
        let source = FileSpeechSource(url: url)
        var transcript = ""
        try await source.start()
        for await fragment in source.fragments where fragment.isFinal {
            transcript += fragment.text + " "
        }
        print("SPIKE transcript:\n\(transcript)")
        // Minimal signal: some Arabic came back. Tighten to an expected word
        // from your clip once you have run it once and seen the output.
        #expect(!transcript.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

/// A class in the test module, so `Bundle(for:)` resolves the test bundle.
private final class SpikeAnchor {}
```

- [ ] **Step 5: Run the spike on the simulator**

Run: `-only-testing:HifzAlMutunTests/FileTranscriptionSpikeTests`
Expected: the test downloads the Arabic model on first run (may take a minute), prints `SPIKE transcript:` with recognizable Arabic words, and passes.

**GATE:** Read the printed transcript. Do the words resemble the recitation (even if imperfect)?
- **Yes →** proceed. Optionally tighten the assertion to check for a specific expected word.
- **No / asset won't install / locale unsupported →** STOP. Record the failure in the spec's Risks section and raise the engine decision (WhisperKit) before continuing.

- [ ] **Step 6: Commit**

```bash
git add Core/Speech/FileSpeechSource.swift Tests/SpeechTests/FileTranscriptionSpikeTests.swift project.yml
git add Tests/SpeechTests/Fixtures/shatibiyya_clip.m4a
git commit -m "feat: file-based SpeechAnalyzer source + Arabic transcription spike (GATE)"
```

---

## Task 9: Fixture accuracy — file source → tracker

Prove the whole non-UI pipeline follows a real recitation: feed the clip through `FileSpeechSource` into a `RecitationTracker` seeded with the matn's opening words and confirm the cursor advances a sensible amount.

**Files:**
- Create: `Tests/SpeechTests/FixtureTrackingTests.swift`

- [ ] **Step 1: Write the test**

Create `Tests/SpeechTests/FixtureTrackingTests.swift`:

```swift
import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct FixtureTrackingTests {
    @available(iOS 26, *)
    @Test func cursorFollowsRecitation() async throws {
        // Load the real Shatibiyyah content from the app bundle.
        let store = await ContentStore()
        let matn = try #require(await store.matn(id: "shatibiyya"))
        let index = RecitationIndex(matn: matn)
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)

        let url = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: "shatibiyya_clip", withExtension: "m4a"))
        let source = FileSpeechSource(url: url)
        try await source.start()
        var t = 0.0
        for await fragment in source.fragments {
            tracker.consume(fragment, at: t)
            t += 0.3
        }
        print("Fixture advanced cursor to \(tracker.cursor) words")
        // A 25s clip should advance through at least a few words of the opening.
        #expect(tracker.cursor >= 4)
    }
}

private final class FixtureAnchor {}
```

> If the matn id is not `"shatibiyya"`, check `Resources/Content/shatibiyya.json`'s `id` field and use that value.

- [ ] **Step 2: Run the test**

Run: `-only-testing:HifzAlMutunTests/FixtureTrackingTests`
Expected: prints the advanced cursor count and passes (`cursor >= 4`). If it advances far less than the clip's spoken words, note it — this is the real-world accuracy signal that informs whether WhisperKit is worth adding later. Lower the threshold only with a comment explaining the observed accuracy.

- [ ] **Step 3: Commit**

```bash
git add Tests/SpeechTests/FixtureTrackingTests.swift
git commit -m "test: fixture recitation advances the tracker end-to-end"
```

---

## Task 10: Memorize reveal rendering

Replace the flat blank in Memorize mode with a word-by-word reveal driven by a revealed-count per hemistich. With no reveal state (mic off) it shows the existing full blank.

**Files:**
- Modify: `Features/Reader/PageView.swift` (the `.memorize` branch of `BaytRow.hemistich`, add a `Revealing` protocol param)
- Create: `Features/Reader/RevealState.swift`
- Create: `Tests/MatchingTests/RevealStateTests.swift`

- [ ] **Step 1: Write the failing test for the reveal-count mapping**

Create `Tests/MatchingTests/RevealStateTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct RevealStateTests {
    private func index() -> RecitationIndex {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: $0) })
        }
        let b = Bayt(number: 1, sadr: hemi(["a", "b"]), ajuz: hemi(["c", "d"]))
        let page = MatnPage(page: 1, items: [.bayt(b)])
        return RecitationIndex(matn: Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t",
            author: "a", meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
            pages: [page], babs: [], reviewNotes: []))
    }

    @Test func mapsCursorToPerHemistichCounts() {
        let r = RevealState(index: index(), cursor: 3)   // a,b,c revealed; d not
        #expect(r.revealedWords(bayt: 1, half: .sadr) == 2)  // both sadr words
        #expect(r.revealedWords(bayt: 1, half: .ajuz) == 1)  // only "c"
    }

    @Test func zeroCursorRevealsNothing() {
        let r = RevealState(index: index(), cursor: 0)
        #expect(r.revealedWords(bayt: 1, half: .sadr) == 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:HifzAlMutunTests/RevealStateTests`
Expected: FAIL — `cannot find 'RevealState' in scope`.

- [ ] **Step 3: Implement RevealState**

Create `Features/Reader/RevealState.swift`:

```swift
import Foundation

/// Answers "how many words of this hemistich are revealed?" from a global
/// cursor, using the flat index's back-references. Precomputes per-(bayt,half)
/// word ranges so lookups during rendering are O(1).
struct RevealState {
    private let cursor: Int
    private var startByHalf: [HalfKey: Int] = [:]
    private var countByHalf: [HalfKey: Int] = [:]

    private struct HalfKey: Hashable { let bayt: Int; let half: Half }

    init(index: RecitationIndex, cursor: Int) {
        self.cursor = cursor
        for (i, ref) in index.refs.enumerated() {
            let key = HalfKey(bayt: ref.bayt, half: ref.half)
            if startByHalf[key] == nil { startByHalf[key] = i }
            countByHalf[key, default: 0] += 1
        }
    }

    /// Number of words revealed in this hemistich (0 … its word count).
    func revealedWords(bayt: Int, half: Half) -> Int {
        let key = HalfKey(bayt: bayt, half: half)
        guard let start = startByHalf[key], let total = countByHalf[key] else { return 0 }
        return min(max(0, cursor - start), total)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `-only-testing:HifzAlMutunTests/RevealStateTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Thread reveal state into PageView**

In `Features/Reader/PageView.swift`, add a reveal parameter and use it in the memorize branch.

Add a stored property to `PageView` (after `let mode: PageMode`):

```swift
    var reveal: RevealState? = nil
```

Pass it down in `body` where `BaytRow(...)` is built, adding this argument to the `BaytRow(` call:

```swift
                                    reveal: reveal,
```

Add the matching stored property to `BaytRow` (after `let mode: PageMode`):

```swift
    var reveal: RevealState? = nil
```

Replace the `.memorize` case of `BaytRow.hemistich(_:)`. Change the signature to know which half it is:

```swift
    @ViewBuilder
    private func hemistich(_ half: Hemistich, which: Half) -> some View {
        switch mode {
        case .read:
            LayeredText(
                rendered: HemistichText.render(
                    segments: half.segments,
                    plain: half.text,
                    size: fontSize,
                    justifyWidth: justifyWidth,
                    tint: inkColor
                ),
                font: PageFont.font(size: fontSize),
                size: fontSize,
                width: columnWidth
            )
        case .memorize:
            MemorizeHalf(
                half: half,
                revealed: reveal?.revealedWords(bayt: bayt.number, half: which) ?? 0,
                fontSize: fontSize,
                columnWidth: columnWidth
            )
        }
    }
```

Update the two call sites in `BaytRow.body` to pass `which:`:

```swift
            hemistich(bayt.sadr, which: .sadr)
            Color.clear.frame(width: midGap)
            hemistich(bayt.ajuz, which: .ajuz)
```

- [ ] **Step 6: Add the MemorizeHalf view**

Add this private view to `Features/Reader/PageView.swift` (near `LayeredText`):

```swift
// A half-line in Memorize mode: the first `revealed` words shown with their real
// colours (filling from the right, RTL), the rest left as a faint blank line.
private struct MemorizeHalf: View {
    let half: Hemistich
    let revealed: Int
    let fontSize: CGFloat
    let columnWidth: CGFloat

    var body: some View {
        let revealedSegments = HemistichReveal.prefix(half, words: revealed)
        let revealedPlain = half.words.prefix(revealed).map(\.text).joined(separator: " ")
        let revealedWidth = PageFont.width(revealedPlain, size: fontSize)
        let blankWidth = max(0, columnWidth - revealedWidth - (revealed > 0 ? 6 : 0))

        HStack(spacing: 6) {
            // Blank remainder on the left (where words are not yet recited).
            if revealed < half.words.count {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.outline)
                    .frame(width: blankWidth, height: 2)
            }
            // Revealed words on the right, at natural size (no kashida).
            if revealed > 0 {
                LayeredText(
                    rendered: HemistichText.render(
                        segments: revealedSegments,
                        plain: revealedPlain,
                        size: fontSize,
                        justifyWidth: 0,
                        tint: inkColor
                    ),
                    font: PageFont.font(size: fontSize),
                    size: fontSize
                )
                .fixedSize()
            }
        }
        .frame(width: columnWidth, alignment: .trailing)
        .frame(height: fontSize * 1.7, alignment: .center)
    }
}
```

> `LayeredText` currently requires a `width` for the fixed-column case; here we pass none (nil) so it sizes to content. Confirm `LayeredText`'s `width` property defaults to `nil` (it does: `var width: CGFloat? = nil`).

- [ ] **Step 7: Build and preview**

Run the build command. Then in Xcode open `PageView.swift` and use the "Memorize — light" preview. Expected: with no reveal state, each hemistich shows the faint blank line exactly as before (reveal defaults to 0).

To eyeball the reveal itself, temporarily change the Memorize preview to pass a reveal state:

```swift
#Preview("Memorize — revealing") {
    let matn = Matn.preview
    let idx = RecitationIndex(matn: matn)
    return PageView(matn: matn, page: 1, mode: .memorize,
                    reveal: RevealState(index: idx, cursor: 5))
}
```

Expected: the first ~5 words of page 1 appear from the right with their colours; the rest stay blank. Remove or keep this preview as you like.

- [ ] **Step 8: Run all tests + build**

Run the whole-suite test command and the build command. Expected: all pass, app builds.

- [ ] **Step 9: Commit**

```bash
git add Features/Reader/PageView.swift Features/Reader/RevealState.swift Tests/MatchingTests/RevealStateTests.swift
git commit -m "feat: word-by-word reveal rendering in Memorize mode"
```

---

## Task 11: AppleSpeechSource — live microphone

Live mic capture → `SpeechAnalyzer`, behind the same `SpeechSource` protocol. Mirrors `FileSpeechSource` but takes audio from `AVAudioEngine` and requests permissions.

**Files:**
- Create: `Core/Speech/AppleSpeechSource.swift`

- [ ] **Step 1: Implement the live source**

Create `Core/Speech/AppleSpeechSource.swift`:

```swift
import Foundation
import AVFoundation
import Speech

/// Live-microphone speech source backed by iOS 26's SpeechAnalyzer. Requests
/// mic + speech-recognition permission, captures audio with AVAudioEngine, and
/// emits recognizer fragments. Same marked lines as FileSpeechSource for the
/// SpeechAnalyzer API — keep them identical.
@available(iOS 26, *)
final class AppleSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let locale: Locale
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var readerTask: Task<Void, Never>?

    init(locale: Locale = Locale(identifier: "ar")) {
        self.locale = locale
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        try await Self.requestPermissions()

        let transcriber = SpeechTranscriber(                   // (1)
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await Self.ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        readerTask = Task { [continuation] in
            do {
                for try await result in transcriber.results {  // (2)
                    continuation.yield(.init(text: String(result.text.characters),
                                             isFinal: result.isFinal))
                }
            } catch { }
            continuation.finish()
        }

        // Audio input stream feeding the analyzer.
        let (inputStream, inputCont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = inputCont

        // Configure the audio session + engine tap.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.inputContinuation?.yield(AnalyzerInput(buffer: buffer))
        }
        engine.prepare()
        try engine.start()

        try await analyzer.start(inputSequence: inputStream)   // (3)
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()
        readerTask?.cancel()
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        try? AVAudioSession.sharedInstance().setActive(false)
        continuation.finish()
    }

    // MARK: - Permissions + model (shared with FileSpeechSource rules)

    private static func requestPermissions() async throws {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { throw SpeechSourceError.notAuthorized }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { throw SpeechSourceError.notAuthorized }
    }

    private static func ensureModel(for transcriber: SpeechTranscriber,
                                    locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else { throw SpeechSourceError.localeUnsupported }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
```

Add the new error case to `Core/Speech/SpeechSource.swift`:

```swift
enum SpeechSourceError: Error { case localeUnsupported, notAuthorized }
```

(Remove the duplicate `SpeechSourceError` declaration from `FileSpeechSource.swift` — keep the single definition in `SpeechSource.swift`.)

- [ ] **Step 2: Build**

Run the build command. Expected: compiles. Fix any SpeechAnalyzer signature mismatches now, keeping the `(1)/(2)/(3)` lines identical to `FileSpeechSource`.

- [ ] **Step 3: Commit**

```bash
git add Core/Speech/AppleSpeechSource.swift Core/Speech/SpeechSource.swift Core/Speech/FileSpeechSource.swift
git commit -m "feat: live-microphone AppleSpeechSource via SpeechAnalyzer"
```

---

## Task 12: RecitationSession — wire source → tracker → reveal

An observable session object the reader owns. Starts/stops a `SpeechSource`, feeds fragments to a `RecitationTracker`, and publishes a `RevealState` + lock state for the UI.

**Files:**
- Create: `Features/Reader/RecitationSession.swift`
- Create: `Tests/MatchingTests/RecitationSessionTests.swift`

- [ ] **Step 1: Write the failing test (using the mock source)**

Create `Tests/MatchingTests/RecitationSessionTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@MainActor
@Suite struct RecitationSessionTests {
    private func index() -> RecitationIndex {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) })
        }
        let b = Bayt(number: 1, sadr: hemi(["يقول", "راجي"]), ajuz: hemi(["عفو", "رب"]))
        return RecitationIndex(matn: Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t",
            author: "a", meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
            pages: [MatnPage(page: 1, items: [.bayt(b)])], babs: [], reviewNotes: []))
    }

    @Test func advancesCursorFromMockFragments() async {
        let mock = MockSpeechSource(script: [
            .init(text: "يقول", isFinal: true),
            .init(text: "راجي", isFinal: true),
        ])
        let session = RecitationSession(index: index(), source: mock, startWordIndex: 0)
        try? await mock.start()   // buffers both fragments, then finishes the stream
        await session.run()       // drains the buffered fragments into the tracker
        #expect(session.cursor == 2)
        #expect(session.reveal.revealedWords(bayt: 1, half: .sadr) == 2)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:HifzAlMutunTests/RecitationSessionTests`
Expected: FAIL — `cannot find 'RecitationSession' in scope`.

- [ ] **Step 3: Implement the session**

Create `Features/Reader/RecitationSession.swift`:

```swift
import Foundation
import SwiftUI

/// Owns a SpeechSource + RecitationTracker and publishes reveal state for the
/// reader. The tracker is pure; this class is the only place audio meets UI.
@MainActor
final class RecitationSession: ObservableObject {
    @Published private(set) var cursor: Int
    @Published private(set) var lockState: LockState = .idle

    private let index: RecitationIndex
    private let tracker: RecitationTracker
    private let source: SpeechSource
    private var pump: Task<Void, Never>?
    private var startTime = Date()

    init(index: RecitationIndex, source: SpeechSource, startWordIndex: Int) {
        self.index = index
        self.source = source
        self.tracker = RecitationTracker(words: index.normalizedWords, startIndex: startWordIndex)
        self.cursor = startWordIndex
    }

    /// Current reveal state derived from the tracker cursor.
    var reveal: RevealState { RevealState(index: index, cursor: cursor) }

    func start() {
        startTime = Date()
        pump = Task { await run() }
        Task { try? await source.start() }
    }

    func stop() {
        source.stop()
        pump?.cancel()
    }

    /// Drains the source stream into the tracker. Exposed for tests.
    func run() async {
        for await fragment in source.fragments {
            tracker.consume(fragment, at: Date().timeIntervalSince(startTime))
            cursor = tracker.cursor
            lockState = tracker.lockState
        }
    }
}
```

> `MockSpeechSource.start()` yields every scripted fragment into the stream's (unbounded) buffer and then finishes it, so the test calls `mock.start()` first and then `session.run()` drains the buffer and returns. The test deliberately does not call `session.start()` (which would also launch the live-source task); it drives `run()` directly.

- [ ] **Step 4: Run to verify it passes**

Run: `-only-testing:HifzAlMutunTests/RecitationSessionTests`
Expected: PASS. If it hangs, apply the note above (call `try? await mock.start()` first in the test).

- [ ] **Step 5: Commit**

```bash
git add Features/Reader/RecitationSession.swift Tests/MatchingTests/RecitationSessionTests.swift
git commit -m "feat: RecitationSession wires speech source to tracker and reveal"
```

---

## Task 13: Hook the session into the reader (mic, reveal, page-turn)

Wire `PageScreen` so tapping the mic starts a live session from the current page, the page reveals as recited, and it auto-turns when the page completes.

**Files:**
- Modify: `Features/Reader/PageScreen.swift`

- [ ] **Step 1: Hold a session and re-publish its state in PageScreen**

In `Features/Reader/PageScreen.swift`, add state (after `@State private var isListening = false`):

```swift
    @StateObject private var voice = VoiceController()
```

`RecitationSession` needs the matn index and a start page, which aren't known until the mic is tapped, and SwiftUI does **not** observe a nested `ObservableObject` automatically. So use a controller that (re)builds a session on demand and **bridges the session's `@Published` values outward** with Combine, so the view re-renders when the cursor moves. Add `import Combine` at the top of the file, and this class at the bottom of `PageScreen.swift`:

```swift
// Owns the live RecitationSession and mirrors its published state so PageScreen
// (which observes THIS object) updates as words are recognised. The session's
// start page isn't known until the user taps the mic, hence the lazy build.
@MainActor
final class VoiceController: ObservableObject {
    @Published private(set) var cursor = 0
    @Published private(set) var lockState: LockState = .idle
    @Published private(set) var reveal: RevealState?

    private var session: RecitationSession?
    private var cancellables: Set<AnyCancellable> = []

    func start(matn: Matn, fromPage page: Int) {
        guard #available(iOS 26, *) else { return }
        let index = RecitationIndex(matn: matn)
        let source = AppleSpeechSource()
        let startIndex = index.firstWordIndex(onPage: page)
        let session = RecitationSession(index: index, source: source, startWordIndex: startIndex)
        self.session = session
        cursor = startIndex
        reveal = RevealState(index: index, cursor: startIndex)

        session.$cursor
            .sink { [weak self] c in
                self?.cursor = c
                self?.reveal = RevealState(index: index, cursor: c)
            }
            .store(in: &cancellables)
        session.$lockState
            .assign(to: &$lockState)

        session.start()
    }

    func stop() {
        session?.stop()
        session = nil
        cancellables.removeAll()
        lockState = .idle
    }
}
```

- [ ] **Step 2: Start/stop the session when listening toggles**

In `PageScreen.body`, the `.onChange(of: mode)` in `footer` already clears `isListening` when leaving memorize. Add an `onChange` for `isListening` on the `TabView` (after `.sheet(...)`):

```swift
        .onChange(of: isListening) { _, listening in
            if listening {
                voice.start(matn: matn, fromPage: currentPage)
            } else {
                voice.stop()
            }
        }
```

- [ ] **Step 3: Feed reveal state into the page + auto page-turn**

Change the `PageView(...)` construction inside the `ForEach` to pass reveal state for the active page only:

```swift
                PageView(matn: matn, page: page, mode: mode,
                         reveal: (mode == .memorize && page == currentPage)
                                 ? voice.reveal : nil)
                    .tag(page)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
```

Add auto page-turn by observing the session cursor. After the `.onChange(of: isListening)` block, add:

```swift
        .onChange(of: voice.cursor) { _, newCursor in
            guard mode == .memorize, isListening else { return }
            let targetPage = pageForCursor(newCursor)
            if targetPage != currentPage {
                withAnimation { currentPage = targetPage }
            }
        }
```

> This fires reliably because `PageScreen` observes `voice` (an `@StateObject`) and `VoiceController.cursor` is its own `@Published` value, bridged from the session in Step 1 — so no nested-observation gap.

Add the helper to `PageScreen`:

```swift
    private func pageForCursor(_ cursor: Int) -> Int {
        guard let ref = sessionRef(at: cursor) else { return currentPage }
        return ref.page
    }
    private func sessionRef(at cursor: Int) -> WordRef? {
        let index = RecitationIndex(matn: matn)
        let clamped = min(max(0, cursor - 1), index.refs.count - 1)
        return index.refs.indices.contains(clamped) ? index.refs[clamped] : nil
    }
```

> Rebuilding `RecitationIndex` here is cheap but repeated; if you prefer, lift the index into `VoiceController` and expose `refs`. Keep it simple for now.

- [ ] **Step 4: Show the lock state near the mic**

In the `footer`, show a small "listening…" caption when lost. After the `MicButton(...)` in `footer`, inside the `if mode == .memorize` block, add:

```swift
                if voice.lockState == .lost {
                    Text("listening…")
                        .font(.caption2)
                        .foregroundStyle(Theme.onChromeDim)
                        .transition(.opacity)
                }
```

- [ ] **Step 5: Build**

Run the build command. Expected: compiles. Resolve any access or optional-chaining issues flagged by the compiler using the patterns above.

- [ ] **Step 6: Run on a real device to verify live recitation** (simulator mic is unreliable)

Set `DEVELOPMENT_TEAM` in `project.yml` to your Apple team id, `xcodegen generate`, select your iPhone, Run. In the app: open the Shatibiyyah, switch to Memorize, tap the mic, grant permissions, and recite the opening. Expected: words reveal from the right as you recite; the page turns when you finish it; pausing shows "listening…" and it re-locks when you resume.

- [ ] **Step 7: Run the full test suite + build**

Run the whole-suite test command. Expected: all unit tests pass.

- [ ] **Step 8: Commit**

```bash
git add Features/Reader/PageScreen.swift
git commit -m "feat: live recitation reveal + auto page-turn in the reader"
```

---

## Task 14: Update MicButton comment + README

Tidy the now-implemented entry point and docs.

**Files:**
- Modify: `Features/Reader/MicButton.swift:3-6` (the "gets wired to this next" comment)
- Modify: `README.md` (Phases list)

- [ ] **Step 1: Update the MicButton comment**

In `Features/Reader/MicButton.swift`, replace the comment that says the engine "gets wired to this next" with a line noting it drives `RecitationSession` in `PageScreen`.

- [ ] **Step 2: Note the feature in the README phases**

In `README.md`, under Phases, mark voice tracking (Memorize word-by-word reveal) as implemented.

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/MicButton.swift README.md
git commit -m "docs: voice tracking wired; update mic comment and README phases"
```

---

## Done

At this point: tapping the mic in Memorize mode follows the reciter, revealing the poem word-by-word with correct colours, turning pages automatically, and recovering gracefully when it loses the thread — all on-device, with the engine behind a swappable `SpeechSource` so WhisperKit can replace Apple's engine later without touching the tracker or UI. Mistake detection is intentionally not built; the tracker's expected-vs-heard comparison is the seam for it.
