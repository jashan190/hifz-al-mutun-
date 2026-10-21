# Menu / Page-Choosing Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the home library as subject-grouped "shelves" with a one-tap Continue card and manuscript title-page covers, and replace the in-reader bottom index sheet with a right-edge overlay sidecar.

**Architecture:** Add a `Subject` taxonomy to the content model and group `ContentStore` by it. Build small, focused SwiftUI views (`MatnCover`, `ContinueCard`, shelf rows, `ReaderSidecar`) on top of the existing `Theme`/`PageFont` tokens. Model/logic changes are covered by Swift Testing unit tests; UI changes are verified by building and running in the iOS Simulator and checking SwiftUI `#Preview`s.

**Tech Stack:** SwiftUI (iOS 26), Swift Testing (`import Testing`), XcodeGen (`project.yml` is source of truth; `.xcodeproj` is generated), Amiri + Aref Ruqaa fonts, CC0 floral-corner asset.

---

## Conventions for every task

- **Project regeneration:** XcodeGen globs `App/`, `Core/`, `Features/` for sources and `Resources/*` for resources. After **creating a new file, font, or asset**, run `xcodegen generate` before building. Editing an existing file needs no regenerate. Never hand-edit `HifzAlMutun.xcodeproj`.
- **Build (simulator):**
  `xcodebuild -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- **Test:**
  `xcodebuild -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test`
- **Run & look:** launch in the Simulator (or use the `/run` skill) and visually confirm. The user prefers build-and-run-in-simulator after every step.
- **Commit** after each task once it builds/tests green. End commit messages with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

# Phase 0 — Foundations (model, tokens, fonts)

### Task 1: `Subject` taxonomy + per-subject colour palette

**Files:**
- Create: `Core/Models/Subject.swift`
- Modify: `Core/Design/Theme.swift` (add subject colour map)
- Test: `Tests/MatchingTests/SubjectTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MatchingTests/SubjectTests.swift
import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct SubjectTests {
    @Test func decodesKnownIdAndFallsBack() throws {
        #expect(Subject(rawValue: "hadith") == .hadith)
        #expect(Subject.from(id: "unknown-xyz") == .quran)   // safe fallback
    }
    @Test func shelfOrderIsStableAndComplete() {
        #expect(Subject.allCases.first == .quran)            // Qur'ān shelf first
        #expect(Subject.allCases.count == 6)
    }
    @Test func everySubjectHasArabicName() {
        for s in Subject.allCases { #expect(!s.arabicName.isEmpty) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command above. Expected: FAIL (`cannot find 'Subject' in scope`).

- [ ] **Step 3: Create the `Subject` type**

```swift
// Core/Models/Subject.swift
import SwiftUI

/// A branch of knowledge a matn belongs to. Drives the home "shelves" and each
/// cover's accent colour. `allCases` order is the shelf order on the home page.
/// Extensible: add a case here + a colour in `Theme.subjectAccent` and the home
/// page grows a new shelf with no other change.
enum Subject: String, CaseIterable, Codable, Hashable {
    case quran, hadith, seerah, aqeedah, arabic, fiqh

    /// Decode a raw id, falling back to `.quran` for anything unknown/missing,
    /// so older content without a subject keeps working.
    static func from(id: String?) -> Subject {
        guard let id, let s = Subject(rawValue: id) else { return .quran }
        return s
    }

    var arabicName: String {
        switch self {
        case .quran:   return "القرآن والتجويد"
        case .hadith:  return "الحديث"
        case .seerah:  return "السيرة"
        case .aqeedah: return "العقيدة"
        case .arabic:  return "العربية"
        case .fiqh:    return "الفقه"
        }
    }

    /// The subject's accent colour (loud, so a shelf reads at a glance).
    var accent: Color { Theme.subjectAccent(self) }
}
```

- [ ] **Step 4: Add the colour map to Theme**

Add inside `enum Theme` in `Core/Design/Theme.swift` (after the `rumuz` colours, before `margin`):

```swift
    // Per-subject accent colours for the library shelves and covers. Saturated
    // on purpose so a subject is recognizable at a glance, even at cover size.
    // Dark values are lightened so titles read on the dark page.
    static func subjectAccent(_ subject: Subject) -> Color {
        switch subject {
        case .quran:   return accent                                   // Madinah green
        case .hadith:  return .dynamic(light: 0xC0362C, dark: 0xE87E76)
        case .seerah:  return .dynamic(light: 0x2A4FC4, dark: 0x8098EE)
        case .aqeedah: return .dynamic(light: 0x5A2E6B, dark: 0xB487C6)
        case .arabic:  return .dynamic(light: 0x6B4A2A, dark: 0xC59C6E)
        case .fiqh:    return .dynamic(light: 0x0E8E86, dark: 0x53C6BE)
        }
    }
```

- [ ] **Step 5: Regenerate, run tests, verify pass**

Run: `xcodegen generate` then the test command. Expected: PASS (new `Subject.swift` picked up).

- [ ] **Step 6: Commit**

```bash
git add Core/Models/Subject.swift Core/Design/Theme.swift Tests/MatchingTests/SubjectTests.swift HifzAlMutun.xcodeproj
git commit -m "Add Subject taxonomy + per-subject accent palette"
```

---

### Task 2: Add `subject` to the `Matn` model

**Files:**
- Modify: `Core/Models/Matn.swift` (struct + Decodable init)
- Modify: `Core/Models/LegacyMatn.swift:120` (memberwise init call)
- Modify: `Core/Models/Matn+Preview.swift:43` (memberwise init call)
- Test: `Tests/MatchingTests/MatnSubjectTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MatchingTests/MatnSubjectTests.swift
import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct MatnSubjectTests {
    // Minimal canonical-v2 matn JSON with an explicit subject.
    private func json(subject: String?) -> Data {
        let subjLine = subject.map { "\"subject\": \"\($0)\"," } ?? ""
        return """
        {
          "schemaVersion": 2, \(subjLine)
          "id": "x", "title": "س", "titleLatin": "x", "author": "a", "meter": "m",
          "baytsPerPage": 10, "pageCount": 1, "baytCount": 1,
          "pages": [{"page": 1, "items": []}],
          "babs": []
        }
        """.data(using: .utf8)!
    }

    @Test func decodesExplicitSubject() throws {
        let m = try JSONDecoder().decode(Matn.self, from: json(subject: "hadith"))
        #expect(m.subject == .hadith)
    }
    @Test func missingSubjectFallsBackToQuran() throws {
        let m = try JSONDecoder().decode(Matn.self, from: json(subject: nil))
        #expect(m.subject == .quran)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL (`value of type 'Matn' has no member 'subject'`).

- [ ] **Step 3: Add the stored property**

In `Core/Models/Matn.swift`, add to the `struct Matn` property list (after `author`):

```swift
    let subject: Subject
```

- [ ] **Step 4: Decode it with fallback**

In the `Matn: Decodable` init in `Core/Models/Matn.swift`, add `subject` to the `Keys` enum:

```swift
        case schemaVersion, id, title, fullTitle, titleLatin, author, meter, subject
```

and in the canonical branch (after `author = ...`):

```swift
        subject = Subject.from(id: try c.decodeIfPresent(String.self, forKey: .subject))
```

- [ ] **Step 5: Fix the two memberwise init call sites**

`Core/Models/LegacyMatn.swift:120` — add `subject:` (legacy v1 files are all Qur'ān/tajwīd):

```swift
        return Matn(
            id: id, title: title, fullTitle: fullTitle, titleLatin: titleLatin,
            author: author, meter: meter, subject: .quran,
            baytsPerPage: baytsPerPage, pageCount: pageCount, baytCount: baytCount,
            pages: pages, babs: canonicalBabs, reviewNotes: []
        )
```

`Core/Models/Matn+Preview.swift:43` — add `subject: .quran,` in the `Matn(` call (place it right after the `author:`/`meter:` arguments, matching the real init's parameter order).

- [ ] **Step 6: Run tests, verify pass**

Expected: PASS. (No regenerate: only edited existing files.)

- [ ] **Step 7: Commit**

```bash
git add Core/Models/Matn.swift Core/Models/LegacyMatn.swift Core/Models/Matn+Preview.swift Tests/MatchingTests/MatnSubjectTests.swift
git commit -m "Matn: add subject (decoded with Qur'an fallback)"
```

---

### Task 3: Group `ContentStore` by subject

**Files:**
- Modify: `Core/Content/ContentStore.swift`
- Test: `Tests/MatchingTests/ContentStoreGroupingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MatchingTests/ContentStoreGroupingTests.swift
import Testing
@testable import HifzAlMutun

@MainActor
@Suite struct ContentStoreGroupingTests {
    @Test func groupsBundledMatnsUnderSubjectsInShelfOrder() {
        let store = ContentStore()
        let shelves = store.shelves
        // Shelves follow Subject.allCases order and skip empty subjects.
        let subjects = shelves.map(\.subject)
        #expect(subjects == subjects.sorted { a, b in
            Subject.allCases.firstIndex(of: a)! < Subject.allCases.firstIndex(of: b)!
        })
        // Every bundled matn appears in exactly one shelf.
        let flat = shelves.flatMap(\.matns)
        #expect(flat.count == store.matns.count)
        // Within a shelf, shortest first (existing convention).
        for shelf in shelves {
            #expect(shelf.matns == shelf.matns.sorted { $0.baytCount < $1.baytCount })
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL (`value of type 'ContentStore' has no member 'shelves'`).

- [ ] **Step 3: Add the `Shelf` type and computed grouping**

In `Core/Content/ContentStore.swift`, add above the class:

```swift
/// One subject's row on the home page: the subject and its mutun (shortest first).
struct Shelf: Identifiable, Hashable {
    let subject: Subject
    let matns: [Matn]
    var id: Subject { subject }
}
```

and add inside `ContentStore`:

```swift
    /// Mutun grouped into shelves, one per subject that has content, in
    /// `Subject.allCases` order. Within a shelf, shortest matn first.
    var shelves: [Shelf] {
        Subject.allCases.compactMap { subject in
            let group = matns.filter { $0.subject == subject }
                             .sorted { $0.baytCount < $1.baytCount }
            return group.isEmpty ? nil : Shelf(subject: subject, matns: group)
        }
    }
```

- [ ] **Step 4: Run tests, verify pass**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Content/ContentStore.swift Tests/MatchingTests/ContentStoreGroupingTests.swift
git commit -m "ContentStore: group mutun into subject shelves"
```

---

### Task 4: Track the most-recently-opened matn (for the Continue card)

**Files:**
- Modify: `Core/Settings/ReadingPosition.swift`
- Modify: `Features/Reader/PageScreen.swift` (record on open)
- Test: `Tests/MatchingTests/ReadingPositionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MatchingTests/ReadingPositionTests.swift
import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct ReadingPositionTests {
    @Test func recordsAndReadsMostRecentMatn() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "lastOpenedMatn")
        #expect(ReadingPosition.mostRecentMatnID == nil)
        ReadingPosition.recordOpened("jazariyya")
        #expect(ReadingPosition.mostRecentMatnID == "jazariyya")
        ReadingPosition.recordOpened("shatibiyya")
        #expect(ReadingPosition.mostRecentMatnID == "shatibiyya")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL (`type 'ReadingPosition' has no member 'mostRecentMatnID'`).

- [ ] **Step 3: Add most-recent tracking**

Append to `enum ReadingPosition` in `Core/Settings/ReadingPosition.swift`:

```swift
    private static let mostRecentKey = "lastOpenedMatn"

    /// The matn the reader opened last (for the Library's Continue card). nil
    /// until any matn has been opened.
    static var mostRecentMatnID: String? {
        UserDefaults.standard.string(forKey: mostRecentKey)
    }

    static func recordOpened(_ matnID: String) {
        UserDefaults.standard.set(matnID, forKey: mostRecentKey)
    }
```

- [ ] **Step 4: Record it when the reader opens**

In `Features/Reader/PageScreen.swift`, find the view `body` and attach an `.onAppear` to the root `TabView` (the one at line ~39 with `.tabViewStyle(.page...)`) that records the open:

```swift
        .onAppear { ReadingPosition.recordOpened(matn.id) }
```

(If an `.onAppear` already exists there, add the `ReadingPosition.recordOpened(matn.id)` line inside it.)

- [ ] **Step 5: Run tests, verify pass; build**

Expected: tests PASS; app builds.

- [ ] **Step 6: Commit**

```bash
git add Core/Settings/ReadingPosition.swift Features/Reader/PageScreen.swift Tests/MatchingTests/ReadingPositionTests.swift
git commit -m "ReadingPosition: track most-recently-opened matn"
```

---

### Task 5: Add the Aref Ruqaa title font + display-font helpers

**Files:**
- Add: `Resources/Fonts/ArefRuqaa-Regular.ttf`, `Resources/Fonts/ArefRuqaa-Bold.ttf` (SIL OFL)
- Create: `Core/Design/DisplayFont.swift`
- Test: `Tests/MatchingTests/DisplayFontTests.swift`

- [ ] **Step 1: Place the font files**

Download Aref Ruqaa (SIL OFL) and copy `ArefRuqaa-Regular.ttf` and `ArefRuqaa-Bold.ttf` into `Resources/Fonts/`. (Google Fonts: https://fonts.google.com/specimen/Aref+Ruqaa — OFL, safe to bundle.) `PageFont.registerBundledFonts()` already registers every `.ttf` in the bundle, so no registration code is needed — only exposure by name.

- [ ] **Step 2: Write the failing test**

```swift
// Tests/MatchingTests/DisplayFontTests.swift
import Testing
import UIKit
@testable import HifzAlMutun

@Suite struct DisplayFontTests {
    @Test func arefRuqaaIsBundledAndRegistered() {
        PageFont.registerBundledFonts()
        #expect(UIFont(name: "Aref Ruqaa", size: 20) != nil)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run `xcodegen generate` (new font files) then the test. Expected: FAIL if the ttf isn't bundled yet / name mismatch. If it fails on the name, confirm the PostScript family name with `UIFont.familyNames` and adjust the string.

- [ ] **Step 4: Add display-font helpers**

```swift
// Core/Design/DisplayFont.swift
import SwiftUI
import UIKit

/// Title / body fonts for the library and covers. Titles are Aref Ruqaa
/// (calligraphic); body text is Amiri. Both are bundled and registered by
/// `PageFont.registerBundledFonts()`. Falls back to the serif system font.
enum DisplayFont {
    static func title(size: CGFloat) -> Font {
        PageFont.registerBundledFonts()
        return UIFont(name: "Aref Ruqaa", size: size) != nil
            ? .custom("Aref Ruqaa", fixedSize: size)
            : .system(size: size, design: .serif)
    }

    static func body(size: CGFloat) -> Font {
        PageFont.registerBundledFonts()
        return UIFont(name: "Amiri", size: size) != nil
            ? .custom("Amiri", fixedSize: size)
            : .system(size: size, design: .serif)
    }
}
```

- [ ] **Step 5: Regenerate, run test, verify pass**

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Resources/Fonts/ArefRuqaa-Regular.ttf Resources/Fonts/ArefRuqaa-Bold.ttf Core/Design/DisplayFont.swift Tests/MatchingTests/DisplayFontTests.swift HifzAlMutun.xcodeproj
git commit -m "Add Aref Ruqaa title font + DisplayFont helpers"
```

---

# Phase 1 — Home: covers, shelves, Continue card

### Task 6: Diamond cross-hatch background

**Files:**
- Create: `Features/Library/HatchBackground.swift`

- [ ] **Step 1: Create the view**

```swift
// Features/Library/HatchBackground.swift
import SwiftUI

/// A faint diamond cross-hatch (two sets of diagonal lines) for the cover
/// "paper", echoing the printed matn title pages. Very low opacity so it only
/// adds texture. Tint defaults to a warm brown; it never competes with content.
struct HatchBackground: View {
    var spacing: CGFloat = 7
    var tint: Color = Color(hex: 0x715A3A).opacity(0.16)

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))   // "/"
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))             // "\"
                x += spacing
            }
            ctx.stroke(path, with: .color(tint), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    HatchBackground()
        .background(Color(hex: 0xF4EBD3))
        .frame(width: 220, height: 280)
}
```

- [ ] **Step 2: Regenerate + build + check the preview**

Run `xcodegen generate`, build, open the `#Preview` in Xcode (or run `/run`). Expected: a faint diamond lattice on cream. Adjust `spacing`/opacity if too strong.

- [ ] **Step 3: Commit**

```bash
git add Features/Library/HatchBackground.swift HifzAlMutun.xcodeproj
git commit -m "Library: diamond cross-hatch cover texture"
```

---

### Task 7: Floral corner ornament asset + `CornerOrnament` view

**Files:**
- Create: `Resources/Assets.xcassets/FloralCorner.imageset/Contents.json`
- Create: `Resources/Assets.xcassets/FloralCorner.imageset/floral-corner.svg`
- Create: `Features/Library/CornerOrnament.swift`
- Source: `DesignAssets/floral-corner-source.svg` (CC0, already in repo)

- [ ] **Step 1: Produce the template SVG from the CC0 source**

The asset must be a **template** image whose *alpha* encodes the two tones (solid blooms at full alpha, leaves at ~30%), so SwiftUI can tint it per subject. Run:

```bash
python3 - <<'PY'
src = open('DesignAssets/floral-corner-source.svg').read()
# blooms/outlines -> opaque black; petal/leaf fills -> 30% black (lighter body)
src = src.replace('fill:#ffffff', 'fill:#000000;fill-opacity:0.3')
src = src.replace('#000000', '#000000')   # outlines already black
open('Resources/Assets.xcassets/FloralCorner.imageset/floral-corner.svg','w').write(src)
print("wrote template svg")
PY
```

- [ ] **Step 2: Create the imageset Contents.json**

```json
{
  "images" : [
    { "filename" : "floral-corner.svg", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

- [ ] **Step 3: Create the `CornerOrnament` view**

```swift
// Features/Library/CornerOrnament.swift
import SwiftUI

/// The four floral corner ornaments of a cover, tinted to the subject colour.
/// One CC0 corner motif (top-left) is mirrored into the other three corners.
/// Edges-only: it hugs each corner and trails lightly along the edges.
struct CornerOrnament: View {
    let color: Color
    var inset: CGFloat = 6
    var size: CGFloat = 62

    var body: some View {
        ZStack {
            corner(.topLeading,     flipX: false, flipY: false)
            corner(.topTrailing,    flipX: true,  flipY: false)
            corner(.bottomLeading,  flipX: false, flipY: true)
            corner(.bottomTrailing, flipX: true,  flipY: true)
        }
        .allowsHitTesting(false)
    }

    private func corner(_ alignment: Alignment, flipX: Bool, flipY: Bool) -> some View {
        Image("FloralCorner")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .scaleEffect(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

#Preview {
    CornerOrnament(color: Color(hex: 0x15803D))
        .background(Color(hex: 0xF4EBD3))
        .frame(width: 220, height: 280)
}
```

- [ ] **Step 4: Regenerate + build + check the preview**

Run `xcodegen generate`, build, open the preview. Expected: four green floral corners, blooms solid, leaves lighter (~30%). If the leaves look fully solid, the template alpha didn't carry — re-check `fill-opacity` survived in the asset SVG, or lower it to `0.25`.

- [ ] **Step 5: Commit**

```bash
git add Resources/Assets.xcassets/FloralCorner.imageset Features/Library/CornerOrnament.swift DesignAssets HifzAlMutun.xcodeproj
git commit -m "Library: tintable floral corner ornament (CC0)"
```

---

### Task 8: `MatnCover` — the manuscript title-page card

**Files:**
- Create: `Features/Library/MatnCover.swift`

- [ ] **Step 1: Create the view**

```swift
// Features/Library/MatnCover.swift
import SwiftUI

/// A poem's custom manuscript "title page": cream paper with a faint diamond
/// hatch, a thin double-rule border, floral corner ornaments, and the title
/// (Aref Ruqaa) + author/label/count (Amiri) — all in the subject's colour.
/// Used at two sizes (hero and shelf) via `style`.
struct MatnCover: View {
    let matn: Matn
    var style: Style = .shelf

    enum Style { case hero, shelf }

    private var color: Color { matn.subject.accent }
    private var cream: Color { .dynamic(light: 0xF4EBD3, dark: 0x262320) }
    private var titleSize: CGFloat { style == .hero ? 34 : 20 }
    private var cornerSize: CGFloat { style == .hero ? 66 : 40 }
    private var cartLabel: String { matn.meter.isEmpty ? "متن" : "منظومة" }

    var body: some View {
        ZStack {
            cream
            HatchBackground()
            CornerOrnament(color: color, inset: style == .hero ? 6 : 4, size: cornerSize)
            doubleRule
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: style == .hero ? 10 : 7, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: style == .hero ? 10 : 6, y: 4)
        .aspectRatio(0.78, contentMode: .fit)   // portrait title-page proportion
    }

    private var doubleRule: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(color.opacity(0.9), lineWidth: 1)
            .padding(style == .hero ? 10 : 7)
            .overlay(
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(color.opacity(0.9), lineWidth: 1)
                    .padding(style == .hero ? 13 : 9)
            )
            .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(spacing: style == .hero ? 10 : 5) {
            Text(cartLabel)
                .font(DisplayFont.body(size: style == .hero ? 12 : 7))
                .foregroundStyle(color)
                .padding(.horizontal, style == .hero ? 12 : 7)
                .padding(.vertical, style == .hero ? 2 : 1)
                .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
            Text(matn.title)
                .font(DisplayFont.title(size: titleSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if style == .hero, !matn.author.isEmpty {
                Text(matn.author)
                    .font(DisplayFont.body(size: 12))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
        }
        .padding(.horizontal, style == .hero ? 28 : 14)
        .overlay(alignment: .bottom) {
            Text("\(Numerals.eastern(matn.baytCount)) بيت")
                .font(DisplayFont.body(size: style == .hero ? 10 : 7))
                .foregroundStyle(color.opacity(0.85))
                .padding(.bottom, style == .hero ? 14 : 8)
        }
    }
}

#Preview("Shelf") {
    HStack {
        MatnCover(matn: .preview, style: .shelf).frame(width: 116)
        MatnCover(matn: .preview, style: .hero).frame(width: 220)
    }
    .padding()
    .background(Color(hex: 0xEADFC6))
}
```

- [ ] **Step 2: Regenerate + build + check the preview**

Expected: a hero and a shelf cover — cream, hatch, double-rule border, floral corners, Aref Ruqaa title, Amiri label/count, all green (`.preview` is `.quran`). Confirm the shelf cover is still legible small.

- [ ] **Step 3: Commit**

```bash
git add Features/Library/MatnCover.swift HifzAlMutun.xcodeproj
git commit -m "Library: MatnCover manuscript title-page card"
```

---

### Task 9: `ContinueCard` — resume the active matn

**Files:**
- Create: `Features/Library/ContinueCard.swift`

- [ ] **Step 1: Create the view**

```swift
// Features/Library/ContinueCard.swift
import SwiftUI

/// Pinned at the top of the Library: the matn the user is in the middle of,
/// with its position and a one-tap resume. Shown only when a last-read position
/// exists. Tapping opens the matn at its exact last page (handled by the caller).
struct ContinueCard: View {
    let matn: Matn
    let lastPage: Int

    private var color: Color { matn.subject.accent }

    private var currentBayt: Int {
        min(matn.baytCount, (lastPage - 1) * matn.baytsPerPage + 1)
    }
    private var progress: Double {
        matn.baytCount > 0 ? Double(currentBayt) / Double(matn.baytCount) : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.22)))
            VStack(alignment: .trailing, spacing: 3) {
                Text("تابِع الحفظ")
                    .font(DisplayFont.body(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                Text(matn.title)
                    .font(DisplayFont.title(size: 24))
                    .foregroundStyle(.white)
                Text("صفحة \(Numerals.eastern(lastPage)) · البيت \(Numerals.eastern(currentBayt)) من \(Numerals.eastern(matn.baytCount))")
                    .font(DisplayFont.body(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                ProgressView(value: progress)
                    .tint(.white)
                    .background(.white.opacity(0.25))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
        .shadow(color: color.opacity(0.35), radius: 10, y: 5)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#Preview {
    ContinueCard(matn: .preview, lastPage: 3)
        .padding()
        .background(Color(hex: 0xFBF8F1))
}
```

- [ ] **Step 2: Regenerate + build + check the preview**

Expected: a green card, RTL, "تابِع الحفظ" + title + position + a thin progress bar.

- [ ] **Step 3: Commit**

```bash
git add Features/Library/ContinueCard.swift HifzAlMutun.xcodeproj
git commit -m "Library: ContinueCard for one-tap resume"
```

---

### Task 10: Rebuild `RootView` as shelves + Continue card

**Files:**
- Modify: `App/RootView.swift` (replace the `MatnCard` list; delete `MatnCard`)

- [ ] **Step 1: Replace the library body**

In `App/RootView.swift`, replace the `library` computed property's `VStack` contents (the `if let error … ForEach … MatnCard …` block) with the Continue card + shelves, and add the two helper views below. Keep the existing `header`, `deepLinkMatn`, `showSettings`, background, and `.sheet`.

```swift
    private var library: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header.appear()

                    if let error = content.loadError {
                        ContentUnavailableView("Content didn't load",
                                               systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        if let (matn, page) = continueTarget {
                            NavigationLink { PageScreen(matn: matn) } label: {
                                ContinueCard(matn: matn, lastPage: page)
                            }
                            .buttonStyle(PressableStyle())
                            .appear()
                        }
                        ForEach(Array(content.shelves.enumerated()), id: \.element.id) { i, shelf in
                            ShelfRow(shelf: shelf)
                                .appear(delay: 0.06 * Double(i + 1))
                        }
                    }
                }
                .padding(Theme.margin)
                .padding(.top, 8)
            }
            .background(Theme.page.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsSheet() }
        }
    }

    /// The matn + last page for the Continue card: the most recently opened
    /// matn that has a saved page. nil if nothing has been opened yet.
    private var continueTarget: (Matn, Int)? {
        guard let id = ReadingPosition.mostRecentMatnID,
              let matn = content.matn(id: id),
              let page = ReadingPosition.lastPage(of: id) else { return nil }
        return (matn, page)
    }
```

- [ ] **Step 2: Add `ShelfRow` (and delete the old `MatnCard`)**

Delete the `private struct MatnCard` entirely. Add:

```swift
/// One subject's shelf: a header and a horizontally scrolling row of covers.
private struct ShelfRow: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(shelf.subject.arabicName)
                .font(DisplayFont.body(size: 17).weight(.bold))
                .foregroundStyle(shelf.subject.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.matns) { matn in
                        NavigationLink { PageScreen(matn: matn) } label: {
                            MatnCover(matn: matn, style: .shelf)
                                .frame(width: 116)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 2)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
```

- [ ] **Step 3: Regenerate (none needed — edited file), build + run in Simulator**

Build and run. Expected: header, a green Continue card once you've opened a matn, and a "القرآن والتجويد" shelf with three covers scrolling RTL. Tapping a cover opens the reader; returning, the Continue card shows the last page.

- [ ] **Step 4: Verify resume**

Open a matn, swipe to a later page, go back to the Library. Expected: Continue card shows that matn + page; tapping it reopens at that page.

- [ ] **Step 5: Commit**

```bash
git add App/RootView.swift
git commit -m "Home: shelves by subject + Continue card (replaces card list)"
```

---

# Phase 2 — In-reader sidecar

### Task 11: `ReaderSidecar` — the navigation panel

**Files:**
- Create: `Features/Reader/ReaderSidecar.swift`

- [ ] **Step 1: Create the view**

Port the `IndexSheet` jump + bab list into a right-edge panel; highlight the current chapter. Reuses `NumberStepperField`, `GoButton`, `Numerals`.

```swift
// Features/Reader/ReaderSidecar.swift
import SwiftUI

/// The in-reader navigation panel: a page/bayt jump and the chapter list, as a
/// right-edge overlay. The current chapter is highlighted. Replaces the old
/// bottom index sheet. The caller owns presentation (overlay + scrim).
struct ReaderSidecar: View {
    let matn: Matn
    @Binding var currentPage: Int
    let onClose: () -> Void

    @State private var mode: JumpMode = .page
    @State private var goToPage = 1
    @State private var goToBayt = 1

    enum JumpMode: String, CaseIterable { case page = "صفحة", bayt = "بيت" }

    private func page(ofBayt bayt: Int) -> Int { (bayt - 1) / matn.baytsPerPage + 1 }
    private var currentBab: Bab? { matn.currentBab(onPage: currentPage) }

    var body: some View {
        VStack(spacing: 0) {
            header
            jump
            Divider().overlay(Theme.chromeHairline)
            chapterList
        }
        .background(Theme.page)
        .onAppear {
            goToPage = currentPage
            goToBayt = (currentPage - 1) * matn.baytsPerPage + 1
        }
    }

    private var header: some View {
        HStack {
            Text(matn.title)
                .font(DisplayFont.title(size: 22))
                .foregroundStyle(Theme.onChrome)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.onChrome.opacity(0.15)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.chrome)
    }

    private var jump: some View {
        VStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(JumpMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                if mode == .page {
                    NumberStepperField(value: $goToPage, range: 1...max(1, matn.pageCount))
                    GoButton { currentPage = goToPage; onClose() }
                } else {
                    NumberStepperField(value: $goToBayt, range: 1...max(1, matn.baytCount))
                    GoButton { currentPage = page(ofBayt: goToBayt); onClose() }
                }
            }
        }
        .padding(14)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var chapterList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(matn.babs) { bab in
                    let isCurrent = bab.id == currentBab?.id
                    Button {
                        currentPage = bab.startPage; onClose()
                    } label: {
                        HStack(spacing: 10) {
                            Text(bab.title)
                                .font(DisplayFont.body(size: 17))
                                .foregroundStyle(isCurrent ? Theme.accent : Theme.ink)
                            Spacer(minLength: 8)
                            Text("ص \(Numerals.eastern(bab.startPage))")
                                .font(.system(.footnote, design: .serif))
                                .foregroundStyle(Theme.numeral)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(isCurrent ? Theme.accent.opacity(0.1) : .clear)
                        .overlay(alignment: .trailing) {
                            if isCurrent {
                                Rectangle().fill(Theme.accent).frame(width: 3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    Divider().overlay(Theme.ink.opacity(0.06)).padding(.leading, 14)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run `xcodegen generate`, build. Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Features/Reader/ReaderSidecar.swift HifzAlMutun.xcodeproj
git commit -m "Reader: ReaderSidecar navigation panel"
```

---

### Task 12: Present the sidecar as a right-edge overlay (replace the sheet)

**Files:**
- Modify: `Features/Reader/PageScreen.swift` (swap `.sheet` for an overlay; remove `IndexSheet`)

- [ ] **Step 1: Replace the sheet with an overlay**

In `Features/Reader/PageScreen.swift`, remove the `.sheet(isPresented: $showIndex) { IndexSheet(...) }` modifier (lines ~62–63) from the `TabView`. Then wrap the reader in a `ZStack` overlay for the sidecar. Add this modifier to the top-level view (where `.sheet` was):

```swift
        .overlay {
            if showIndex {
                ZStack(alignment: .trailing) {
                    // Scrim: dims the page, tap to dismiss.
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showIndex = false } }

                    ReaderSidecar(matn: matn, currentPage: $currentPage) {
                        withAnimation(.easeOut(duration: 0.2)) { showIndex = false }
                    }
                    .frame(width: UIScreen.main.bounds.width * 0.8)
                    .frame(maxHeight: .infinity)
                    .background(Theme.page)
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: showIndex)
```

- [ ] **Step 2: Open from the ☰ button with animation**

The index button already sets `showIndex = true` (line ~170). Wrap it so it animates:

```swift
            ChromeIconButton(system: "list.bullet", label: "Index") {
                withAnimation(.easeOut(duration: 0.22)) { showIndex = true }
            }
```

- [ ] **Step 3: Delete the old `IndexSheet`**

Remove the entire `private struct IndexSheet: View { … }` (lines ~416–535) from `PageScreen.swift`. `NumberStepperField`/`GoButton` live in `Components.swift` and stay.

- [ ] **Step 4: Build + run in Simulator**

Open a matn, tap ☰. Expected: the panel slides in from the **right** over a dimmed page; the current chapter is highlighted; the صفحة/بيت segmented jump works; tapping a chapter navigates and closes; tapping the dim area or ✕ closes. Swiping to turn pages still works when the panel is closed.

- [ ] **Step 5: Commit**

```bash
git add Features/Reader/PageScreen.swift
git commit -m "Reader: right-edge sidecar overlay replaces index sheet"
```

---

# Phase 3 — Verification & sign-off

### Task 13: Dark mode pass + device sign-off

**Files:** none (verification; small token tweaks only if needed)

- [ ] **Step 1: Dark mode check**

Run in the Simulator in Dark Appearance. Confirm: subject colours (`subjectAccent` dark values), cream cover ground (`0x262320`), hatch, border, and Continue card all read well. Tweak dark hex values in `Theme.subjectAccent` / `MatnCover.cream` if any are low-contrast.

- [ ] **Step 2: Full build + test**

Run the test command. Expected: all suites PASS. Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Device sign-off**

Build + install on the iPhone (per the earlier device workflow). Confirm home shelves, covers (real Aref Ruqaa/Amiri), Continue resume, and the sidecar all behave on-device.

- [ ] **Step 4: Commit any tweaks**

```bash
git add -A
git commit -m "Polish: dark-mode subject colours + sign-off tweaks"
```

---

## Self-review notes

- **Spec coverage:** Subject taxonomy+palette (T1), subject on Matn (T2), shelves (T3), Continue/most-recent (T4,T9,T10), fonts (T5), hatch (T6), floral corners (T7), cover component (T8), home layout (T10), sidecar panel (T11), right-edge overlay replacing the sheet (T12), assets/fonts/XcodeGen note (conventions + T5,T7), dark mode + verification (T13). All spec sections map to a task.
- **Deferred (spec "open questions"):** "active matn" = most-recent-with-saved-page (T10 `continueTarget`); `الكل ›` see-all screen left out of this pass (shelves show all mutun in a scrollable row); flower density is the single `fill-opacity` in T7; dark shades finalized in T13.
- **Type consistency:** `Subject.from(id:)`, `Subject.accent`/`Theme.subjectAccent`, `ContentStore.shelves`/`Shelf`, `ReadingPosition.mostRecentMatnID`/`recordOpened`, `DisplayFont.title`/`.body`, `MatnCover(matn:style:)`, `ContinueCard(matn:lastPage:)`, `ReaderSidecar(matn:currentPage:onClose:)` are used consistently across tasks.
