# Mistake Highlighting & Session Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mark memorization mistakes with a red highlight **box** (text colour unchanged) so flagged words are visible on the page and don't clash with red hadith text, clear a flag by long-press, and make the Session Review point clearly at each mistake.

**Architecture:** A mistake "box" is a soft-red **background highlight** applied as a run attribute (`backgroundColor` on `AttributedString` for poems, `.backgroundColor` on `NSAttributedString` for hadith) — one mechanism across both renderers, no custom glyph drawing, text colour untouched. Flagged words (from the existing `FlagStore`) get the box in read mode; long-press removes a flag. Prose live mistakes switch from red text to the signal-red box. The Session Review enlarges the expected-vs-heard line, makes the location prominent, and flashes the word on jump.

**Tech Stack:** SwiftUI (iOS 26), Swift Testing, SwiftData (FlagStore, unchanged). Build/test sim id `0F8C82CA-6844-40E1-B260-9F1024DB07EC` (iOS 26.5; `-showdestinations` if gone; ignore the "IOSurfaceClientSetSurfaceNotify" line). Device UDID `83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941`. Run `xcodegen generate` after adding files.

**Spec:** `docs/superpowers/specs/2026-10-21-mistake-highlighting-review-design.md` (refinement: the box is a filled background highlight, not a custom rounded/bordered box — rounding/border is a device-tunable follow-up, not in this plan).

**Reused facts:**
- `FlagStore` (MainActor): `isFlagged(_ matnID:String, _ key:FlagKey) -> Bool`, `setFlag(_ on:Bool, matnID:String, _ key:FlagKey)`. `FlagKey(bayt:Int, half:Half, wordIndex:Int)` — prose: `bayt` = hadith number, `half` = `.sadr`, `wordIndex` = word-in-body.
- `Theme.error` (`#C62828`/`#EF6B6B`), `Theme.flag` (`#B4532A`), `Theme.ink`, `Theme.cover`, `Theme.rumuz`.
- Poem read-mode hemistich: `PageView.swift` `BaytRow.hemistich(_:which:)` calls `HemistichText.render(segments:plain:size:justifyWidth:tint:underlined:emphasis:)` with `underlined: ranges.indices.filter { flagged(which,$0) }.map { ranges[$0] }` and a `.contextMenu` that flags/unflags each word. `HemistichReveal.wordRanges(in:)` returns `[Range<Int>]` (scalar ranges per word).
- `HemistichText.render` builds an `AttributedString`; its inner `add(_:color:slot:underline:)` sets `basePiece.underlineStyle` for underlined ranges (line ~189, using `Theme.flag`).
- Prose: `ProsePageView.swift` renders `JustifiedText(attributed: ProseText.attributed(fragment.words, font:, lineSpacing:, color:, underline:))`. `ProseText.attributed(_ words:font:lineSpacing:color:(Int,ProseRole)->UIColor, underline:(Int)->UIColor?)`. `ProsePageView` has `fragment` (`hadithNumber`, `bodyStart`, `words`), `subjectColor`, `reveal: RevealState?`, and the `shown`/`wordColor` helpers. Prose live `.wrong` currently returns `Theme.rumuz`.
- Session Review: `PageScreen.swift` `SummaryCard` + `MistakeRow` (shows `place`, `expected` with differing letters in `Theme.error`, "you said" heard). `ReviewSummary.Mistake { id, page, bayt, half, wordIndex, expected, heard, added }`. The jump is a `show: { mistake in … currentPage = … }` closure.

**Shared box colours (used throughout):** fill `Theme.error.opacity(0.14)`, and for prose `UIColor(Theme.error).withAlphaComponent(0.14)`. (Tunable on device.)

---

## File map

- **Modify:** `Core/Design/HemistichText.swift` (add a `boxed:` param → `backgroundColor`), `Features/Reader/PageView.swift` (`BaytRow` passes flagged ranges as `boxed`; flash support), `Features/Reader/ProseText.swift` (add a `background:` closure), `Features/Reader/ProsePageView.swift` (flagged-word backgrounds in read mode, live-mistake box + signal-red, flag context menu, flash), `Features/Reader/PageScreen.swift` (`MistakeRow` enlarge + prominent location; `flashTarget` state + pulse on jump).
- **Test:** `Tests/MatchingTests/MistakeBoxTests.swift` (pure range/index resolution + HemistichText background attribute).

---

## Task 1: Poem flagged words get a background box (read mode)

Replace the flag **underline** with a soft-red **background highlight** on flagged words.

**Files:** Modify `Core/Design/HemistichText.swift`, `Features/Reader/PageView.swift`; Test `Tests/MatchingTests/MistakeBoxTests.swift`.

- [ ] **Step 1: Write the failing test** — Create `Tests/MatchingTests/MistakeBoxTests.swift`:

```swift
import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct MistakeBoxTests {
    @Test func renderBoxesFlaggedWordWithBackground() {
        // "في النظم" → two words; box the second (range of "النظم").
        let plain = "في النظم"
        let ranges = HemistichReveal.wordRanges(in: plain)
        let rendered = HemistichText.render(
            segments: [Segment(text: plain, color: .black, footnote: nil)],
            plain: plain, size: 30, justifyWidth: 200,
            tint: { _ in Theme.ink },
            boxed: [ranges[1]])
        // Somewhere in the base string, a run carries the box background colour.
        let hasBox = rendered.base.runs.contains { $0.backgroundColor != nil }
        #expect(hasBox)
    }
}
```

- [ ] **Step 2: Run it — verify it FAILS** (`render` has no `boxed:` param).

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,id=0F8C82CA-6844-40E1-B260-9F1024DB07EC' -only-testing:HifzAlMutunTests/MistakeBoxTests`
Expected: FAIL (missing `boxed:` argument). Run `xcodegen generate` first if the file isn't found.

- [ ] **Step 3: Add `boxed:` to `HemistichText.render`** — READ `Core/Design/HemistichText.swift`. Add a `boxed: [Range<Int>] = []` parameter after `underlined`. In the inner `add(_ text:color:slot:underline:)` helper, add a `box: Bool = false` argument and, when `box`, set the background colour on the base piece:

```swift
        func add(_ text: String, color: Color, slot: Slot, underline: Bool = false, box: Bool = false) {
            // … existing body that builds `basePiece` …
            if underline { basePiece.underlineStyle = Text.LineStyle(pattern: .solid, color: Theme.flag) }
            if box { basePiece.backgroundColor = Theme.error.opacity(0.14) }   // mistake highlight
            // … existing append …
        }
```

At the call site that currently computes `underline: underlined.contains { $0.contains(pidx) }`, also compute and pass `box: boxed.contains { $0.contains(pidx) }`. (Locate the single `add(...)` call for plain text, ~line 242, and add the `box:` argument mirroring the `underline:` one.)

- [ ] **Step 4: Run the test — verify it PASSES.**

- [ ] **Step 5: Switch `BaytRow` from underline to box** — In `Features/Reader/PageView.swift` `BaytRow.hemistich(_:which:)` read case, change the flagged-ranges argument from `underlined:` to `boxed:`:

```swift
                rendered: HemistichText.render(
                    segments: half.segments,
                    plain: half.text,
                    size: fontSize,
                    justifyWidth: justifyWidth,
                    tint: inkColor,
                    boxed: ranges.indices.filter { flagged(which, $0) }.map { ranges[$0] }
                ),
```

(Keep the `.contextMenu` flag/unflag block exactly as-is — long-press-to-clear for poems already works through it.)

- [ ] **Step 6: Build** — `xcodegen generate && xcodebuild build ... | grep -E "error:|BUILD SUCCEEDED"` → BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Core/Design/HemistichText.swift Features/Reader/PageView.swift Tests/MatchingTests/MistakeBoxTests.swift
git commit -m "Poem mistakes: red background box for flagged words (read mode)"
```

---

## Task 2: Prose flagged words get a background box (read mode)

Give `ProseText.attributed` a per-word background closure and have `ProsePageView` box the hadith's flagged words from `FlagStore` in read mode.

**Files:** Modify `Features/Reader/ProseText.swift`, `Features/Reader/ProsePageView.swift`; Test add to `Tests/MatchingTests/MistakeBoxTests.swift` + `ProseTextTests.swift`.

- [ ] **Step 1: Add a failing test** — In `Tests/MatchingTests/ProseTextTests.swift` add:

```swift
    @Test func attributedAppliesPerWordBackground() {
        let a = ProseText.attributed(words, font: .systemFont(ofSize: 20), lineSpacing: 8,
            color: { _, _ in .black }, underline: { _ in nil },
            background: { i in i == 1 ? .yellow : nil })
        let i2 = (a.string as NSString).range(of: "إِنَّمَا").location
        #expect(a.attribute(.backgroundColor, at: i2, effectiveRange: nil) as? UIColor == .yellow)
        #expect(a.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }
```

- [ ] **Step 2: Run it — verify it FAILS** (`attributed` has no `background:`).

- [ ] **Step 3: Add the `background:` closure to `ProseText.attributed`** — READ `Features/Reader/ProseText.swift`. Add a parameter `background: (_ index: Int) -> UIColor? = { _ in nil }` and apply it:

```swift
    static func attributed(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                           color: (_ index: Int, _ role: ProseRole) -> UIColor,
                           underline: (_ index: Int) -> UIColor?,
                           background: (_ index: Int) -> UIColor? = { _ in nil }) -> NSAttributedString {
        // … existing para setup …
        for (i, w) in words.enumerated() {
            if i > 0 { /* existing joining space — leave as-is */ }
            var attrs: [NSAttributedString.Key: Any] =
                [.font: font, .foregroundColor: color(i, w.role), .paragraphStyle: para]
            if let u = underline(i) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = u
            }
            if let bg = background(i) { attrs[.backgroundColor] = bg }
            out.append(NSAttributedString(string: w.text, attributes: attrs))
        }
        return out
    }
```

The existing `body(...)` wrapper keeps compiling (background defaults to nil). The default also keeps Task-earlier callers compiling.

- [ ] **Step 4: Run both prose text tests — verify PASS** (`attributedAppliesPerWordColourAndUnderline`, `attributedAppliesPerWordBackground`).

- [ ] **Step 5: Box flagged words in `ProsePageView` (read mode)** — READ `Features/Reader/ProsePageView.swift`. `ProsePageView` needs the `FlagStore` and the matn id. Add:

```swift
    @EnvironmentObject private var flagStore: FlagStore
    let matnID: String
```

(Its call site in `PageView` must pass `matnID: matn.id` — update that in Step 6.)

Add a helper that returns the box colour for a word, and pass it as the `background:` closure. A word is boxed when it's flagged (read mode only — in memorize the live reveal owns colours; live mistake boxes are Task 4):

```swift
    private func wordBackground(_ j: Int) -> UIColor? {
        guard reveal == nil else { return nil }   // flag boxes are a read-mode aid
        let key = FlagKey(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j)
        return flagStore.isFlagged(matnID, key) ? UIColor(Theme.error).withAlphaComponent(0.14) : nil
    }
```

Add `background: { j in wordBackground(j) }` to the `ProseText.attributed(...)` call in `body`.

- [ ] **Step 6: Pass `matnID` from `PageView`** — In `Features/Reader/PageView.swift` the `.hadith` arm:

```swift
                            case .hadith(let fragment):
                                ProsePageView(fragment: fragment,
                                              subjectColor: matn.subject.accent,
                                              matnID: matn.id,
                                              reveal: mode == .memorize ? reveal : nil)
```

`PageView` already has `@EnvironmentObject flagStore` (used by `BaytRow`); confirm `ProsePageView` receives the environment object (it does, via the view tree — `PageScreen` injects `FlagStore` as an `@EnvironmentObject`). If `FlagStore` isn't an environment object on `PageScreen`, read how `BaytRow` obtains it and mirror that.

- [ ] **Step 7: Build** — BUILD SUCCEEDED. (A `#Preview` for `ProsePageView`, if any, needs `.environmentObject(FlagStore.inMemory())` and a `matnID:` argument — update it.)

- [ ] **Step 8: Commit**

```bash
git add Features/Reader/ProseText.swift Features/Reader/ProsePageView.swift Features/Reader/PageView.swift Tests/MatchingTests/ProseTextTests.swift
git commit -m "Hadith mistakes: red background box for flagged words (read mode)"
```

---

## Task 3: Long-press a hadith to remove its flags

Poems already have long-press-to-clear (the hemistich context menu). Add the equivalent for hadith: long-press the paragraph → a menu of the flagged words on this page, each "Remove flag".

**Files:** Modify `Features/Reader/ProsePageView.swift`. Verified by build + device.

- [ ] **Step 1: Add a context menu listing the fragment's flagged words** — In `ProsePageView.body`, attach a `.contextMenu` to the `JustifiedText(...)` body paragraph that lists the flagged words among `fragment.words` (read mode), each removing its flag:

```swift
            JustifiedText(attributed: ProseText.attributed(/* … as before, with background: … */))
                .frame(maxWidth: .infinity)
                .contextMenu {
                    let flagged = fragment.words.indices.filter {
                        flagStore.isFlagged(matnID, FlagKey(bayt: fragment.hadithNumber,
                                                            half: .sadr, wordIndex: fragment.bodyStart + $0))
                    }
                    if flagged.isEmpty {
                        Text("No flagged words on this page")
                    } else {
                        ForEach(flagged, id: \.self) { j in
                            Button("Remove flag: \(fragment.words[j].text)", systemImage: "flag.slash") {
                                flagStore.setFlag(false, matnID: matnID,
                                    FlagKey(bayt: fragment.hadithNumber, half: .sadr,
                                            wordIndex: fragment.bodyStart + j))
                            }
                        }
                    }
                }
```

(Scope: removing is the primary ask; manual flagging of a prose word by hand is out — prose flags come from voice review. The menu lists only this page's flagged words.)

- [ ] **Step 2: Build** — BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ProsePageView.swift
git commit -m "Hadith: long-press to remove a flagged word's box"
```

---

## Task 4: Prose live mistakes use the signal-red box (not red text)

During recitation, a wrong hadith word should stand out from red matn text: give it the signal-red **box** and the signal-red letter colour (instead of `Theme.rumuz`).

**Files:** Modify `Features/Reader/ProsePageView.swift`.

- [ ] **Step 1: Switch the `.wrong` colour + add a live box** — In `ProsePageView.wordColor`, change the `.wrong` case from `Theme.rumuz` to `Theme.error`:

```swift
        case .wrong: return UIColor(Theme.error)            // said wrong (signal-red, not content-red)
```

Extend `wordBackground(_:)` so that in MEMORIZE mode a wrong/skipped word also gets a box (reusing the same background mechanism), while read mode uses the flag boxes from Task 2:

```swift
    private func wordBackground(_ j: Int) -> UIColor? {
        if let reveal {    // memorize: box the live mistakes
            switch reveal.outcome(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j) {
            case .wrong, .skipped: return UIColor(Theme.error).withAlphaComponent(0.12)
            default: return nil
            }
        }
        // read mode: box flagged words
        let key = FlagKey(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j)
        return flagStore.isFlagged(matnID, key) ? UIColor(Theme.error).withAlphaComponent(0.14) : nil
    }
```

- [ ] **Step 2: Build** — BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ProsePageView.swift
git commit -m "Hadith live mistakes: signal-red box + text (clear of matn red)"
```

---

## Task 5: Session Review — prominent location, bigger expected-vs-heard, flash on jump

**Files:** Modify `Features/Reader/PageScreen.swift` (`MistakeRow` + the `show:` closure/flash state), `Features/Reader/PageView.swift` + `Features/Reader/ProsePageView.swift` (render a transient flash box).

- [ ] **Step 1: Make the `MistakeRow` location prominent and the expected-vs-heard bigger** — In `PageScreen.swift` `MistakeRow.body`, enlarge the `place` label and the words. Replace the `VStack`'s content:

```swift
                VStack(alignment: .leading, spacing: 3) {
                    Text(place)
                        .font(.subheadline.weight(.semibold))      // was .caption
                        .foregroundStyle(Theme.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mistake.added ? "After" : "Should be")
                            .font(.footnote).foregroundStyle(Theme.ink.opacity(0.7))
                        Text(expected)
                            .font(PageFont.font(size: 24))          // was 20
                        Text(mistake.added ? "· you added" : mistake.heard == nil ? "· skipped" : "· you said")
                            .font(.footnote).foregroundStyle(Theme.error)
                        if let heard = mistake.heard {
                            Text(heard)
                                .font(PageFont.font(size: 24))
                                .foregroundStyle(Theme.error)
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
```

- [ ] **Step 2: Add a flash target to `PageScreen`** — Add state and set it in the `show:` closure after computing the jump target:

```swift
    /// A word to briefly flash after jumping to a mistake (then it clears).
    @State private var flashTarget: FlagKey?
```

In the `SummaryCard(... show: { mistake in … })` closure, after setting `currentPage = target`, add:

```swift
                                    let key = FlagKey(bayt: mistake.bayt,
                                                      half: mistake.half, wordIndex: mistake.wordIndex)
                                    flashTarget = key
                                    Task {
                                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                                        if flashTarget == key { flashTarget = nil }
                                    }
```

Pass `flashTarget` into `PageView`: add `flashTarget: FlagKey?` to `PageView` and forward from the `ForEach`:

```swift
                ForEach(displayPages, id: \.page) { pageModel in
                    PageView(matn: matn, pageModel: pageModel, mode: mode,
                             reveal: mode == .memorize ? voice.reveal : nil,
                             flashTarget: flashTarget)
```

- [ ] **Step 3: Render the flash box (poems)** — In `PageView`, thread `var flashTarget: FlagKey? = nil` through `BaytRow`. In `BaytRow.hemistich` read case, include the flashed word in the `boxed:` ranges with a stronger look. Simplest: box the flashed word too (it already boxes flagged words); to make the flash visible even on a non-flagged mistake, compute a `flashRange`:

```swift
            let flashRange: [Range<Int>] = {
                guard let f = flashTarget, f.bayt == bayt.number, f.half == which,
                      f.wordIndex < ranges.count else { return [] }
                return [ranges[f.wordIndex]]
            }()
            // boxed = flagged ∪ flashed
            boxed: Array(Set(ranges.indices.filter { flagged(which, $0) }.map { ranges[$0] } + flashRange))
```

(The persistent flagged box and the transient flash box share the same look; the flash simply makes a box appear for ~1.2s on the jumped-to word if it wasn't already flagged. A brighter pulse is a device-tunable follow-up.)

- [ ] **Step 4: Render the flash box (hadith)** — In `PageView`'s `.hadith` arm pass `flashTarget: flashTarget` to `ProsePageView` (add the param). In `ProsePageView.wordBackground` read-mode branch, also box the flashed word:

```swift
        // read mode: box flagged words (and the transient flash target)
        let key = FlagKey(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j)
        if flagStore.isFlagged(matnID, key) { return UIColor(Theme.error).withAlphaComponent(0.14) }
        if flashTarget == key { return UIColor(Theme.error).withAlphaComponent(0.22) }
        return nil
```

Add `var flashTarget: FlagKey? = nil` to `ProsePageView`.

- [ ] **Step 5: Build + full suite** — `xcodegen generate && xcodebuild test ... 2>&1 | grep -E "✘ Test|BUILD FAILED|error:" | head`. Expected: BUILD SUCCEEDED; only the pre-existing `everyMatnHasItsPhonemes` (bayqūniyya) failure; no other regressions.

- [ ] **Step 6: Commit**

```bash
git add Features/Reader/PageScreen.swift Features/Reader/PageView.swift Features/Reader/ProsePageView.swift
git commit -m "Session review: prominent location, bigger expected/heard, flash word on jump"
```

---

## Task 6: Device check

**No code (unless fixes needed).** Build + deploy and verify.

- [ ] **Step 1: Deploy** (the standard device build/install/launch block).

- [ ] **Step 2: Verify on device:** flag a poem word (long-press → Flag) → it shows a soft-red box in read mode; long-press → Remove flag → box gone. Recite a hadith, make a mistake → the wrong word shows a signal-red box (clear of the red matn text) during review; after the sitting, read mode shows the boxes; long-press the hadith → Remove flag clears one. Open Session Review, tap a mistake → it jumps and the word flashes a box; confirm the location label is prominent and the "should be X · you said Y" is larger. Confirm poems' live memorize colouring is unchanged.

- [ ] **Step 3:** No commit (verification only). Report issues for follow-up.

---

## Notes for the implementer
- **The box is a filled background highlight** (`backgroundColor` run attribute), not a custom rounded/bordered box — one mechanism for poems (`AttributedString`) and hadith (`NSAttributedString`). Rounded corners / border = a later device-tunable refinement, out of scope here.
- **Poem live colouring is untouched** — Task 1 only changes the read-mode flagged treatment (underline → box). The memorize `MemorizeWord` path is unchanged.
- Box opacities (`0.14` read, `0.12`/`0.22` live/flash) are starting points — tune on device.
- `FlagStore` is reused unchanged; no schema or API change.
