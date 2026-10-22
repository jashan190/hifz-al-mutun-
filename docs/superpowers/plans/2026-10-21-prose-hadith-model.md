# Prose Hadith Content Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the app read prose hadith (al-Arbaʿīn al-Nawawiyya, 42 hadith) alongside the bayt poems — display/read-only — by extending `Matn` with a prose kind and flowing each hadith across swipe-pages at runtime.

**Architecture:** Approach A from the spec — one `Matn` model with `kind: poem | prose`. A prose matn stores `[Hadith]` (semantic units). A pure `ProsePaginator` flows them into `[MatnPage]` of `PageItem.hadith` fragments at load (each hadith starts a fresh page). The existing paged reader, index, cover, and reading-position code are reused; a new `ProsePageView` renders a fragment as a justified paragraph.

**Tech Stack:** Swift 5.9 / SwiftUI (iOS 26), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), XcodeGen (`project.yml`; regenerate with `xcodegen generate`), Python 3 build tooling (`Tools/build_matn.py`, `Tools/normalize.py`).

**Spec:** `docs/superpowers/specs/2026-10-21-prose-hadith-model-design.md`

**Conventions used throughout:**
- Swift tests live in `Tests/MatchingTests/*.swift` and are run with:
  `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16'`
  (substitute any booted simulator name from `xcrun simctl list devices available`).
- Python builder tests are plain `assert` scripts run with `python3 <path>` (exit 0 = pass).
- Device build/deploy (for the manual display checks) uses the project's known device:
  ```bash
  xcodebuild -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -configuration Debug \
    -destination 'platform=iOS,id=83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941' \
    -derivedDataPath ./build/DerivedData -allowProvisioningUpdates build
  APP=$(find ./build/DerivedData/Build/Products -maxdepth 2 -name "HifzAlMutun.app" -path "*iphoneos*" | head -1)
  xcrun devicectl device install app --device 83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941 "$APP"
  ```
- After adding/removing files on disk, run `xcodegen generate` (globs pick up `App/`, `Core/`, `Features/`, `Tests/`).

---

## File map

**Create:**
- `Core/Models/Hadith.swift` — prose value types: `MatnKind`, `ProseRole`, `ProseWord`, `Hadith`, `HadithFragment`.
- `Features/Reader/ProsePaginator.swift` — pure paginator (`[Hadith]` → `[MatnPage]` + first-page map).
- `Features/Reader/ProseText.swift` — pure helper building the role-coloured `AttributedString` for a hadith body.
- `Features/Reader/ProsePageView.swift` — renders one `HadithFragment` (heading / justified body / takhrīj).
- `Tools/tests/test_build_prose.py` — builder test (role tagging + structure).
- `Tools/sources/arbaeen.txt` — hand-verified source transcription.
- `Resources/Content/arbaeen.json` — built content (bundled, auto-discovered).
- `Tests/MatchingTests/ProsePaginatorTests.swift`, `Tests/MatchingTests/ProseModelTests.swift`, `Tests/MatchingTests/ProseTextTests.swift` — Swift tests.

**Modify:**
- `Core/Models/Matn.swift` — `.hadith` PageItem case; `kind`/`hadiths` on `Matn`; decoder; `hadithFragments(onPage:)`.
- `Tools/build_matn.py` — prose branch keyed on `% kind = prose`.
- `Features/Reader/PageView.swift` — take a `MatnPage` model; render the `.hadith` case.
- `Features/Reader/PageScreen.swift` — compute prose pages+babs via the paginator; drive the reader from a resolved page list.
- `Features/Library/MatnCover.swift` — kind-aware count label and cartouche.

---

## Task 1: Prose model types

**Files:**
- Create: `Core/Models/Hadith.swift`
- Test: `Tests/MatchingTests/ProseModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MatchingTests/ProseModelTests.swift`:

```swift
import Testing
@testable import HifzAlMutun

@Suite struct ProseModelTests {
    @Test func proseWordDecodesRole() throws {
        let json = #"{"text":"إِنَّمَا","norm":"انما","role":"matn"}"#.data(using: .utf8)!
        let w = try JSONDecoder().decode(ProseWord.self, from: json)
        #expect(w.text == "إِنَّمَا")
        #expect(w.normalized == "انما")
        #expect(w.role == .matn)
    }

    @Test func hadithDecodesFully() throws {
        let json = """
        {"number":1,"title":"الحديث الأول",
         "body":[{"text":"عَنْ","norm":"عن","role":"isnad"},
                 {"text":"إِنَّمَا","norm":"انما","role":"matn"}],
         "takhrij":"رواه البخاري ومسلم"}
        """.data(using: .utf8)!
        let h = try JSONDecoder().decode(Hadith.self, from: json)
        #expect(h.number == 1)
        #expect(h.id == 1)
        #expect(h.title == "الحديث الأول")
        #expect(h.body.count == 2)
        #expect(h.body[0].role == .isnad)
        #expect(h.body[1].role == .matn)
        #expect(h.takhrij == "رواه البخاري ومسلم")
    }

    @Test func fragmentFlagsAreStored() {
        let frag = HadithFragment(hadithNumber: 3, title: "الحديث الثالث",
                                  words: [], takhrij: "رواه مسلم",
                                  isFirst: true, isLast: false)
        #expect(frag.hadithNumber == 3)
        #expect(frag.isFirst && !frag.isLast)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:HifzAlMutunTests/ProseModelTests`
Expected: FAIL — `Cannot find type 'ProseWord'/'Hadith'/'HadithFragment' in scope`.

- [ ] **Step 3: Create the model file**

Create `Core/Models/Hadith.swift`:

```swift
import Foundation

/// Whether a matn is verse (sadr/ajuz bayts) or flowing prose (hadith).
enum MatnKind: String, Decodable, Hashable { case poem, prose }

/// The part of a hadith a word belongs to, which decides its colour.
/// Takhrīj is not a role — it is a separate footer string on `Hadith`.
enum ProseRole: String, Decodable, Hashable {
    case isnad   // chain + narration frame — normal ink
    case matn    // the Prophet's words (the «…» spans) — subject colour
}

/// A word in a hadith body: display text, normalised form (for future voice/
/// memorize matching), and the role that decides its colour.
struct ProseWord: Decodable, Hashable {
    let text: String
    let normalized: String
    let role: ProseRole

    enum CodingKeys: String, CodingKey { case text, normalized = "norm", role }
}

/// One hadith: its number, heading, the body as an ordered word sequence
/// (isnād + matn interleaved, each word role-tagged) and the takhrīj line.
struct Hadith: Decodable, Hashable, Identifiable {
    let number: Int
    let title: String        // e.g. "الحديث الأول"
    let body: [ProseWord]
    let takhrij: String      // e.g. "رواه البخاري ومسلم"
    var id: Int { number }
}

/// A page-sized slice of one hadith, produced by `ProsePaginator` at runtime
/// (never decoded). `isFirst` → render the heading above it; `isLast` → render
/// the takhrīj below it; `words` is the slice shown on this page.
struct HadithFragment: Hashable {
    let hadithNumber: Int
    let title: String
    let words: [ProseWord]
    let takhrij: String
    let isFirst: Bool
    let isLast: Bool
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:HifzAlMutunTests/ProseModelTests`
Expected: PASS (3 tests). (New files under `Core/` are globbed; no `xcodegen` needed because the paths already exist in the target — if the test can't find the file, run `xcodegen generate` and retry.)

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Core/Models/Hadith.swift Tests/MatchingTests/ProseModelTests.swift
git commit -m "Prose model: MatnKind, ProseWord, Hadith, HadithFragment"
```

---

## Task 2: `PageItem.hadith` case + `Matn` prose fields + decoding

**Files:**
- Modify: `Core/Models/Matn.swift`
- Test: `Tests/MatchingTests/ProseModelTests.swift` (add a decode test)

- [ ] **Step 1: Add the failing test**

Append to `Tests/MatchingTests/ProseModelTests.swift` (inside the `@Suite`):

```swift
    @Test func proseMatnDecodesAndPoemsStillDecode() throws {
        let prose = """
        {"schemaVersion":1,"id":"x","title":"الأربعون","titleLatin":"arbaeen",
         "author":"النووي","meter":"","subject":"hadith","kind":"prose",
         "baytsPerPage":0,"pageCount":0,"baytCount":2,
         "pages":[],"babs":[],
         "hadiths":[{"number":1,"title":"الحديث الأول",
           "body":[{"text":"عَنْ","norm":"عن","role":"isnad"}],
           "takhrij":"رواه مسلم"}]}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(Matn.self, from: prose)
        #expect(m.kind == .prose)
        #expect(m.hadiths.count == 1)
        #expect(m.baytCount == 2)        // repurposed as hadith count
        #expect(m.pages.isEmpty)
        #expect(m.subject == .hadith)

        // Regression: a poem (no kind, no hadiths) still decodes as .poem.
        let poem = """
        {"schemaVersion":1,"id":"y","title":"ت","titleLatin":"t","author":"a",
         "meter":"الرجز","subject":"quran","baytsPerPage":10,"pageCount":1,
         "baytCount":1,"pages":[{"page":1,"items":[]}],"babs":[]}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Matn.self, from: poem)
        #expect(p.kind == .poem)
        #expect(p.hadiths.isEmpty)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProseModelTests/proseMatnDecodesAndPoemsStillDecode`
Expected: FAIL — `Matn` has no member `kind`/`hadiths`.

- [ ] **Step 3: Add the `.hadith` PageItem case**

In `Core/Models/Matn.swift`, change the `PageItem` enum (currently lines ~75-78) to:

```swift
/// An item in a page's print order.
enum PageItem: Hashable {
    case heading(Heading)
    case bayt(Bayt)
    case hadith(HadithFragment)   // produced by ProsePaginator, never decoded
}
```

Leave the `extension PageItem: Decodable` block **unchanged** — the on-disk schema only ever contains `heading`/`bayt`; `.hadith` is built at runtime.

- [ ] **Step 4: Add `kind`/`hadiths` to `Matn` and decode them**

In `struct Matn` (lines ~115-129), add two stored properties after `subject`:

```swift
    let subject: Subject
    let kind: MatnKind            // poem (bayts) or prose (hadith)
    let hadiths: [Hadith]         // prose only; empty for poems
    let baytsPerPage: Int
    let pageCount: Int
    let baytCount: Int            // bayt count for poems; hadith count for prose
```

In the `Keys` enum (line ~135), add `kind, hadiths`:

```swift
        case schemaVersion, id, title, fullTitle, titleLatin, author, meter, subject
        case kind, hadiths
        case baytsPerPage, pageCount, baytCount, pages, babs, reviewNotes
```

In `init(from:)`, the legacy fallback (lines ~141-144) must still produce a poem. Update `LegacyMatn.canonical()` callers by giving `canonical()` the new fields (Task handled below in Step 5). In the canonical branch, after `subject = ...` (line ~152) add:

```swift
        kind = try c.decodeIfPresent(MatnKind.self, forKey: .kind) ?? .poem
        hadiths = try c.decodeIfPresent([Hadith].self, forKey: .hadiths) ?? []
```

- [ ] **Step 5: Keep the legacy path compiling**

`LegacyMatn.canonical()` constructs a `Matn(...)` (in `Core/Models/LegacyMatn.swift`, lines ~121-126). Add the two new arguments so poems built from the v1 schema stay poems. Change that initializer call to include:

```swift
        return Matn(
            id: id, title: title, fullTitle: fullTitle, titleLatin: titleLatin,
            author: author, meter: meter, subject: Subject.from(id: subject),
            kind: .poem, hadiths: [],
            baytsPerPage: baytsPerPage, pageCount: pageCount, baytCount: baytCount,
            pages: pages, babs: canonicalBabs, reviewNotes: []
        )
```

- [ ] **Step 6: Add the fragment lookup**

In the `extension Matn` convenience lookups (after `bayts(onPage:)`, ~line 174), add:

```swift
    /// The hadith fragments on a page (prose), in order.
    func hadithFragments(onPage n: Int) -> [HadithFragment] {
        items(onPage: n).compactMap {
            if case .hadith(let f) = $0 { return f } else { return nil }
        }
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProseModelTests`
Expected: PASS (4 tests). If other suites reference `Matn(...)` directly (e.g. `Matn+Preview.swift`), update those initializer calls to pass `kind: .poem, hadiths: []` — grep: `grep -rn "Matn(" Core Features Tests | grep -v "MatnPage\|MatnCover\|MatnKind"`. Fix each call site, then re-run the full suite:
`xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS (all suites green).

- [ ] **Step 8: Commit**

```bash
git add Core/Models/Matn.swift Core/Models/LegacyMatn.swift Tests/MatchingTests/ProseModelTests.swift
# plus any Matn(...) call sites updated
git commit -m "Matn: prose kind + hadiths, .hadith page item, decoding"
```

---

## Task 3: Builder prose branch

**Files:**
- Modify: `Tools/build_matn.py`
- Test: `Tools/tests/test_build_prose.py`

- [ ] **Step 1: Write the failing builder test**

Create `Tools/tests/test_build_prose.py`:

```python
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Tools/

SRC = """% id = t
% title = عنوان
% titleLatin = t
% author = مؤلف
% subject = hadith
% kind = prose

@ 1 | الحديث الأول
عَنْ عُمَرَ قَالَ: «إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ»
= رواه البخاري ومسلم

@ 2 | الحديث الثاني
عَنْ أَبِي هُرَيْرَةَ
= رواه مسلم
"""

def main():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "t.txt"); out = os.path.join(d, "t.json")
        open(src, "w", encoding="utf-8").write(SRC)
        subprocess.run([sys.executable, os.path.join(ROOT, "build_matn.py"), src, out], check=True)
        doc = json.load(open(out, encoding="utf-8"))

    assert doc["kind"] == "prose", doc.get("kind")
    assert doc["baytCount"] == 2, doc["baytCount"]
    assert doc["pages"] == [] and doc["babs"] == []
    assert doc["pageCount"] == 0 and doc["baytsPerPage"] == 0
    hs = doc["hadiths"]; assert len(hs) == 2, len(hs)

    h1 = hs[0]
    assert h1["number"] == 1 and h1["title"] == "الحديث الأول"
    assert h1["takhrij"] == "رواه البخاري ومسلم"
    roles = {w["text"]: w["role"] for w in h1["body"]}
    # words inside «…» are matn; the rest isnad
    assert roles["عَنْ"] == "isnad"
    assert roles["«إِنَّمَا"] == "matn" or roles.get("إِنَّمَا") == "matn"
    # guillemets stripped from stored text
    assert all("«" not in w["text"] and "»" not in w["text"] for w in h1["body"]), \
        [w["text"] for w in h1["body"]]
    # a matn word is present and normalised
    matn_words = [w for w in h1["body"] if w["role"] == "matn"]
    assert matn_words and all(w["norm"] for w in matn_words)
    print("OK")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 Tools/tests/test_build_prose.py`
Expected: FAIL — the builder raises `ValueError` (bayt parser hits the prose lines) or produces no `kind`/`hadiths`.

- [ ] **Step 3: Add the prose branch to `build_matn.py`**

In `Tools/build_matn.py`, add a prose parser and dispatch on `% kind = prose`. First add, near the top after `SCHEMA_VERSION = 1`:

```python
import re

_HARAKAT = re.compile(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]')
```

Add a prose source parser:

```python
def parse_prose_source(path):
    """Parse a prose (hadith) source: metadata, then per hadith a '@ n | title'
    header, body lines, and a '= takhrij' line. Text inside «…» is matn."""
    meta = {}
    hadiths = []
    current = None   # {number, title, body_lines[], takhrij}

    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("%"):
                key, _, value = s[1:].partition("=")
                meta[key.strip()] = value.strip()
                continue
            if s.startswith("@"):
                body = s[1:].strip()
                num_str, _, title = body.partition("|")
                current = {"number": int(num_str.strip()),
                           "title": title.strip(), "body_lines": [], "takhrij": ""}
                hadiths.append(current)
                continue
            if s.startswith("="):
                if current is None:
                    raise ValueError(f"{path}:{lineno}: '=' takhrij before any '@' hadith")
                current["takhrij"] = s[1:].strip()
                continue
            if current is None:
                raise ValueError(f"{path}:{lineno}: body before any '@' hadith")
            current["body_lines"].append(s)

    return meta, hadiths


def prose_words(text):
    """Split body text into role-tagged words. Text inside «…» is 'matn',
    everything else 'isnad'. Guillemets are stripped from stored text."""
    out = []
    in_matn = False
    buf = []
    role = "isnad"

    def flush():
        nonlocal buf
        if buf:
            w = "".join(buf)
            if w:
                out.append({"text": w, "norm": normalize(w), "role": role})
            buf = []

    for ch in text:
        if ch == "«":
            flush(); in_matn = True; role = "matn"; continue
        if ch == "»":
            flush(); in_matn = False; role = "isnad"; continue
        if ch.isspace():
            flush(); continue
        buf.append(ch)
    flush()
    return out


def build_prose(meta, hadiths):
    out_hadiths = []
    for h in hadiths:
        body_text = " ".join(h["body_lines"])
        words = prose_words(body_text)
        if not words:
            raise ValueError(f"hadith {h['number']} has an empty body")
        out_hadiths.append({
            "number": h["number"], "title": h["title"],
            "body": words, "takhrij": h["takhrij"],
        })
    # numbers must be contiguous from 1
    nums = [h["number"] for h in out_hadiths]
    assert nums == list(range(1, len(nums) + 1)), f"hadith numbers not 1..N: {nums}"
    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": meta.get("id", ""),
        "title": meta.get("title", ""),
        "fullTitle": meta.get("fullTitle", ""),
        "titleLatin": meta.get("titleLatin", ""),
        "author": meta.get("author", ""),
        "meter": meta.get("meter", ""),
        "subject": meta.get("subject", "hadith"),
        "kind": "prose",
        "baytsPerPage": 0,
        "pageCount": 0,
        "baytCount": len(out_hadiths),   # hadith count
        "pages": [],
        "babs": [],
        "hadiths": out_hadiths,
    }
```

Then in `main(argv)`, dispatch on kind. Replace the body of `main` that currently does `meta, babs, bayts = parse_source(src); doc = build(meta, babs, bayts)` with:

```python
    src, dst = argv[1], argv[2]
    # Peek at the kind without consuming the parser.
    kind = "poem"
    with open(src, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("%"):
                k, _, v = s[1:].partition("=")
                if k.strip() == "kind":
                    kind = v.strip()
    if kind == "prose":
        meta, hadiths = parse_prose_source(src)
        doc = build_prose(meta, hadiths)
    else:
        meta, babs, bayts = parse_source(src)
        doc = build(meta, babs, bayts)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    if kind == "prose":
        print(f"wrote {dst}: {doc['baytCount']} hadith (prose)")
    else:
        print(
            f"wrote {dst}: {doc['baytCount']} bayts, {len(doc['babs'])} babs, "
            f"{doc['pageCount']} pages ({doc['baytsPerPage']}/page)"
        )
    return 0
```

(Keep the existing `if len(argv) != 3` guard at the top of `main`.)

- [ ] **Step 4: Run the builder test to verify it passes**

Run: `python3 Tools/tests/test_build_prose.py`
Expected: prints `OK`, exit 0.

- [ ] **Step 5: Verify poems still build (regression)**

Run: `python3 Tools/build_matn.py Tools/sources/tuhfa.txt /tmp/tuhfa_check.json && python3 -c "import json;d=json.load(open('/tmp/tuhfa_check.json'));print(d.get('kind','poem'), d['baytCount'], len(d['babs']))"`
Expected: `poem 61 10` (kind absent in poem output ⇒ `.poem` on decode; builder need not emit `kind` for poems).

- [ ] **Step 6: Commit**

```bash
git add Tools/build_matn.py Tools/tests/test_build_prose.py
git commit -m "build_matn: prose (hadith) branch with «…» matn tagging"
```

---

## Task 4: `ProsePaginator` (pure)

**Files:**
- Create: `Features/Reader/ProsePaginator.swift`
- Test: `Tests/MatchingTests/ProsePaginatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MatchingTests/ProsePaginatorTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import HifzAlMutun

@Suite struct ProsePaginatorTests {
    private func word(_ i: Int) -> ProseWord {
        ProseWord(text: "w\(i)", normalized: "w\(i)", role: .isnad)
    }
    private func hadith(_ n: Int, words: Int) -> Hadith {
        Hadith(number: n, title: "ح\(n)", body: (0..<words).map(word),
               takhrij: "رواه")
    }
    // Deterministic measure: each word is 1.0 tall (one word per "line").
    private let measure: ([ProseWord]) -> CGFloat = { CGFloat($0.count) }

    @Test func shortHadithIsOnePageBothFlags() {
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 3)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 1)
        let f = frag(pages[0])
        #expect(f.isFirst && f.isLast)
        #expect(f.words.count == 3)
        #expect(first[1] == 1)
    }

    @Test func longHadithSplitsAcrossPages() {
        // bodyHeight 10, heading 2 → first page fits 8 words, next pages 10.
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 15)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 2)
        #expect(frag(pages[0]).isFirst && !frag(pages[0]).isLast)
        #expect(!frag(pages[1]).isFirst && frag(pages[1]).isLast)
        // words partition exactly, in order, no loss or dupe
        let all = frag(pages[0]).words + frag(pages[1]).words
        #expect(all.map(\.text) == (0..<15).map { "w\($0)" })
        #expect(frag(pages[0]).words.count == 8)   // 10 - heading 2
        #expect(first[1] == 1)
    }

    @Test func secondHadithStartsFreshPage() {
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 3), hadith(2, words: 2)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 2)                 // one page each, never shared
        #expect(frag(pages[0]).hadithNumber == 1)
        #expect(frag(pages[1]).hadithNumber == 2)
        #expect(first[1] == 1 && first[2] == 2)
        #expect(pages[0].page == 1 && pages[1].page == 2)
    }

    private func frag(_ p: MatnPage) -> HadithFragment {
        guard case .hadith(let f) = p.items[0] else { fatalError("not a hadith page") }
        return f
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProsePaginatorTests`
Expected: FAIL — `Cannot find 'ProsePaginator' in scope`.

- [ ] **Step 3: Implement the paginator**

Create `Features/Reader/ProsePaginator.swift`:

```swift
import CoreGraphics
import UIKit

/// Flows hadith (semantic units) into page-sized fragments. Each hadith starts
/// a fresh page; a short one leaves its page partly empty, a long one spills
/// onto further pages. The takhrīj is rendered on the last fragment but is not
/// height-reserved — minor overflow is absorbed by the page's scroll view.
enum ProsePaginator {
    /// - Parameters:
    ///   - bodyHeight: vertical space available for body text on a page.
    ///   - headingHeight: space the title block takes on a hadith's first page.
    ///   - takhrijHeight: unused by the split (kept for callers/clarity).
    ///   - measureBody: wrapped height of the given words at the content width.
    /// - Returns: the pages (1…N) and a map hadith number → its first page.
    static func paginate(_ hadiths: [Hadith],
                         bodyHeight: CGFloat,
                         headingHeight: CGFloat,
                         takhrijHeight: CGFloat,
                         measureBody: ([ProseWord]) -> CGFloat)
    -> (pages: [MatnPage], firstPageOf: [Int: Int]) {
        var pages: [MatnPage] = []
        var firstPageOf: [Int: Int] = [:]
        var pageNo = 0

        for h in hadiths {
            firstPageOf[h.number] = pageNo + 1
            var rest = h.body
            var first = true
            repeat {
                pageNo += 1
                let cap = max(1, bodyHeight - (first ? headingHeight : 0))
                let n = max(1, fit(rest, cap: cap, measure: measureBody))  // always progress
                let slice = Array(rest.prefix(n))
                rest = Array(rest.dropFirst(n))
                let isLast = rest.isEmpty
                pages.append(MatnPage(page: pageNo, items: [.hadith(
                    HadithFragment(hadithNumber: h.number, title: h.title,
                                   words: slice, takhrij: h.takhrij,
                                   isFirst: first, isLast: isLast))]))
                first = false
            } while !rest.isEmpty
        }
        return (pages, firstPageOf)
    }

    /// Largest prefix count whose measured height is ≤ cap (at least 0; the
    /// caller guarantees ≥1 word is taken). Binary search over prefix length.
    private static func fit(_ words: [ProseWord], cap: CGFloat,
                            measure: ([ProseWord]) -> CGFloat) -> Int {
        if words.isEmpty { return 0 }
        if measure(words) <= cap { return words.count }
        var lo = 1, hi = words.count, best = 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if measure(Array(words.prefix(mid))) <= cap { best = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return best
    }

    // MARK: Default measurement (used by the reader, not by tests)

    /// Wrapped height of a run of words at `width`, using the page font.
    static func bodyHeight(_ words: [ProseWord], width: CGFloat, font: UIFont) -> CGFloat {
        let s = words.map(\.text).joined(separator: " ")
        guard !s.isEmpty, width > 0 else { return 0 }
        let rect = (s as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return ceil(rect.height)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProsePaginatorTests`
Expected: PASS (3 tests). (Run `xcodegen generate` first if the new file isn't found.)

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Features/Reader/ProsePaginator.swift Tests/MatchingTests/ProsePaginatorTests.swift
git commit -m "ProsePaginator: flow hadith into page fragments (pure + TextKit measure)"
```

---

## Task 5: `ProseText` helper + `ProsePageView`

**Files:**
- Create: `Features/Reader/ProseText.swift`, `Features/Reader/ProsePageView.swift`
- Test: `Tests/MatchingTests/ProseTextTests.swift`

- [ ] **Step 1: Write the failing test for the text helper**

Create `Tests/MatchingTests/ProseTextTests.swift`:

```swift
import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct ProseTextTests {
    @Test func joinsWordsWithSpaces() {
        let words = [
            ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
            ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn),
        ]
        let s = ProseText.plain(words)
        #expect(s == "عَنْ إِنَّمَا")
    }

    @Test func attributedColoursByRole() {
        let words = [
            ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
            ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn),
        ]
        let a = ProseText.attributed(words, isnad: .black, matn: .red)
        // Two runs with distinct colours, in order.
        let runs = Array(a.runs)
        #expect(runs.count >= 2)
        #expect(String(a.characters).contains("عَنْ"))
        #expect(String(a.characters).contains("إِنَّمَا"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProseTextTests`
Expected: FAIL — `Cannot find 'ProseText' in scope`.

- [ ] **Step 3: Implement the text helper**

Create `Features/Reader/ProseText.swift`:

```swift
import SwiftUI

/// Builds the display text for a hadith body: a single string so wrapping and
/// justification are natural, with each word coloured by its role.
enum ProseText {
    /// Plain joined text (spaces between words).
    static func plain(_ words: [ProseWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    /// One `AttributedString` with isnād words in `isnad` and the Prophet's
    /// words (matn) in `matn`. A single space (isnād-coloured) joins words.
    static func attributed(_ words: [ProseWord], isnad: Color, matn: Color) -> AttributedString {
        var out = AttributedString()
        for (i, w) in words.enumerated() {
            if i > 0 {
                var sp = AttributedString(" ")
                sp.foregroundColor = isnad
                out += sp
            }
            var piece = AttributedString(w.text)
            piece.foregroundColor = (w.role == .matn) ? matn : isnad
            out += piece
        }
        return out
    }
}
```

- [ ] **Step 4: Run the helper test to verify it passes**

Run: `xcodebuild test ... -only-testing:HifzAlMutunTests/ProseTextTests` (run `xcodegen generate` first)
Expected: PASS (2 tests).

- [ ] **Step 5: Implement the page view (no new test; verified by build + Task 6 device check)**

Create `Features/Reader/ProsePageView.swift`:

```swift
import SwiftUI

/// Renders one `HadithFragment`: the heading (first page), the justified body
/// paragraph (Prophet's words in the subject colour), and the takhrīj (last
/// page). The folio is drawn by the containing `PageView`.
struct ProsePageView: View {
    let fragment: HadithFragment
    let subjectColor: Color
    /// Fixed, comfortable reading size for prose (not auto-fitted like poems).
    var fontSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            if fragment.isFirst {
                Text(fragment.title)
                    .font(DisplayFont.title(size: fontSize * 0.9))
                    .foregroundStyle(subjectColor)
                    .multilineTextAlignment(.center)
            }
            Text(ProseText.attributed(fragment.words, isnad: Theme.ink, matn: subjectColor))
                .font(PageFont.font(size: fontSize))
                .multilineTextAlignment(.leading)   // justified RTL paragraph
                .lineSpacing(fontSize * 0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
            if fragment.isLast && !fragment.takhrij.isEmpty {
                Text(fragment.takhrij)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
```

- [ ] **Step 6: Verify it builds**

Run: `xcodegen generate && xcodebuild build -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Features/Reader/ProseText.swift Features/Reader/ProsePageView.swift Tests/MatchingTests/ProseTextTests.swift
git commit -m "Prose rendering: ProseText (role colouring) + ProsePageView"
```

---

## Task 6: Reader integration (PageView + PageScreen) and cover

**Files:**
- Modify: `Features/Reader/PageView.swift`, `Features/Reader/PageScreen.swift`, `Features/Library/MatnCover.swift`

This task wires prose into the reader. No unit test (view/integration); verified by build + the Task 7 device check. Work in small compiles.

- [ ] **Step 1: Make `PageView` render a `MatnPage` model (and the `.hadith` case)**

`PageView` currently takes `page: Int` and looks up `matn.items(onPage: page)`. Change it to take the resolved page so it works for both poem (`matn.pages`) and prose (paginated) sources.

In `Features/Reader/PageView.swift`, change the stored properties (top of the struct) from `let page: Int` to:

```swift
    let pageModel: MatnPage
```

In `body`, replace the first lines inside `GeometryReader { geo in` :

```swift
            let items = pageModel.items
            let bayts = items.compactMap { if case .bayt(let b) = $0 { return b } else { return nil } }
```

Add the `.hadith` case to the `switch item` (alongside `.heading`/`.bayt`):

```swift
                            case .hadith(let fragment):
                                ProsePageView(fragment: fragment,
                                              subjectColor: matn.subject.accent)
```

In the `folio` computed view, replace `Text(Numerals.eastern(page))` with `Text(Numerals.eastern(pageModel.page))`, and in its `.accessibilityLabel("Page \(page)")` use `pageModel.page`.

If `PageView` has a `#Preview`, update it to pass a `MatnPage` (e.g. `MatnPage(page: 1, items: [])`).

- [ ] **Step 2: Add a resolved page list to `PageScreen`**

In `Features/Reader/PageScreen.swift`, add state and a resolver. After the existing `@State` declarations (around line 19) add:

```swift
    /// For prose: pages produced by the paginator for the current geometry, and
    /// the per-hadith index built from them. Empty for poems.
    @State private var prosePages: [MatnPage] = []
    @State private var proseBabs: [Bab] = []

    /// The pages the reader actually shows: poem pages come straight from the
    /// matn; prose pages are paginated at runtime.
    private var displayPages: [MatnPage] {
        matn.kind == .prose ? prosePages : matn.pages
    }
    private var displayPageCount: Int { displayPages.count }
    private var displayBabs: [Bab] {
        matn.kind == .prose ? proseBabs : matn.babs
    }
```

- [ ] **Step 3: Drive the `TabView` from `displayPages`**

Replace the `TabView` body (lines ~31-44) so it iterates the resolved pages and paginates prose on appearance / size change:

```swift
        GeometryReader { geo in
            TabView(selection: $currentPage) {
                MatnCover(matn: matn, style: .page)
                    .tag(0)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
                ForEach(displayPages, id: \.page) { pageModel in
                    PageView(matn: matn, pageModel: pageModel, mode: mode,
                             reveal: mode == .memorize ? voice.reveal : nil)
                        .tag(pageModel.page)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleBars() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: geo.size) { repaginateIfProse(in: geo.size) }
        }
```

Keep the rest of `body` (the `.onAppear`, `.safeAreaInset`, overlays, etc.) as-is, but move those modifiers onto the `GeometryReader` (they currently hang off `TabView`). If that reparenting is awkward, instead wrap only the paging content: keep `TabView` where it is and add an outer `GeometryReader` around the whole `body` content, calling `.task(id:)` on it. Either way the paginator needs `geo.size`.

Add the paginate method in the `extension`/body of `PageScreen`:

```swift
    private func repaginateIfProse(in size: CGSize) {
        guard matn.kind == .prose, size.width > 0, size.height > 0 else { return }
        let fontSize: CGFloat = 24
        let hMargin = Theme.margin * 2
        let folio: CGFloat = 34
        let contentWidth = size.width - hMargin
        let bodyHeight = size.height - folio - Theme.margin * 2
        let font = PageFont.uiFont(size: fontSize)         // see Step 4
        let headingHeight = fontSize * 1.6
        let (pages, firstPageOf) = ProsePaginator.paginate(
            matn.hadiths,
            bodyHeight: bodyHeight,
            headingHeight: headingHeight,
            takhrijHeight: fontSize * 1.6,
            measureBody: { ProsePaginator.bodyHeight($0, width: contentWidth, font: font) })
        prosePages = pages
        proseBabs = matn.hadiths.map {
            Bab(id: "h\($0.number)", title: $0.title, startPage: firstPageOf[$0.number] ?? 1)
        }
        // Clamp the resume page now that we know the count.
        if currentPage > pages.count { currentPage = max(1, pages.count) }
    }
```

- [ ] **Step 4: Add `PageFont.uiFont(size:)`**

`ProsePaginator.bodyHeight` and the view must measure/render with the *same* font. In `Core/Design/PageFont.swift`, if there is no `UIFont` accessor, add one next to `font(size:)`/`width(_:size:)` (reuse whatever font name those use — mirror `width`'s implementation, which already constructs a `UIFont`):

```swift
    /// The page font as a UIFont, for TextKit measurement. Mirrors `font(size:)`.
    static func uiFont(size: CGFloat) -> UIFont {
        UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }
```

(Use the exact font-name constant `width(_:size:)` already references; if `width` builds its font inline, extract that name into a `fontName` constant and use it in both.)

- [ ] **Step 5: Point the reader's page-count readers at `displayPageCount`/`displayBabs`**

In `PageScreen`:
- `init`: the clamp `min(max(1, page), matn.pageCount)` can't use `matn.pageCount` for prose (it's 0). Change to:
  ```swift
  _currentPage = State(initialValue: startOnCover ? 0 : max(1, page))
  ```
  (The resume page is clamped against the real count in `repaginateIfProse`; for poems it was already within range.)
- The footer counter (lines ~238-239) `"\(…currentPage) / \(…matn.pageCount)"` → use `displayPageCount`.
- `babsCaption` (line ~187) `matn.currentBab(onPage:)` uses `matn.babs`. Add a reader-local current-bab that uses `displayBabs`:
  ```swift
  private var babsCaption: String {
      displayBabs.last { $0.startPage <= currentPage }?.title ?? ""
  }
  ```
- Pass `displayBabs` to `ReaderSidecar`. In `ReaderSidecar.swift`, the index currently reads `matn.babs`; add a `var babs: [Bab]` parameter (defaulting to `matn.babs` is not possible with stored `matn`, so make it required) and iterate `babs` instead of `matn.babs`; have its `currentBab` use `babs`. Update the `ReaderSidecar(...)` call site in `PageScreen` to pass `babs: displayBabs`.

- [ ] **Step 6: Make the cover count label kind-aware**

In `Features/Library/MatnCover.swift`, the bottom overlay currently reads:

```swift
Text("\(Numerals.eastern(matn.baytCount)) بيت")
```

Replace with a kind-aware unit, and update `cartLabel` for prose. Change `cartLabel`:

```swift
    private var cartLabel: String {
        switch matn.kind {
        case .prose: return "الأربعون"
        case .poem:  return matn.meter.isEmpty ? "متن" : "منظومة"
        }
    }
```

and the count overlay:

```swift
Text(matn.kind == .prose
     ? "\(Numerals.eastern(matn.baytCount)) حديثًا"
     : "\(Numerals.eastern(matn.baytCount)) بيت")
```

- [ ] **Step 7: Build for the simulator**

Run: `xcodegen generate && xcodebuild build -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`. Fix any compile errors (common: a missed `page` → `pageModel.page` in `PageView`, or a `Matn(...)` call site).

- [ ] **Step 8: Run the full test suite (regression)**

Run: `xcodebuild test -project HifzAlMutun.xcodeproj -scheme HifzAlMutun -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: all suites pass (poem reader paths untouched behaviourally).

- [ ] **Step 9: Commit**

```bash
git add Features/Reader/PageView.swift Features/Reader/PageScreen.swift \
        Features/Reader/ReaderSidecar.swift Features/Library/MatnCover.swift \
        Core/Design/PageFont.swift
git commit -m "Reader: render prose via paginated pages; kind-aware cover"
```

---

## Task 7: Content — author & build `arbaeen.json`, verify on device

**Files:**
- Create: `Tools/sources/arbaeen.txt`, `Resources/Content/arbaeen.json`

The vocalised matn text is in `/tmp/arbaeen.html` (takw.in, basmala + 42 hadith with harakat, Prophet-speech already in `«…»`). This task turns it into the source file and builds it. **The user verifies the Arabic text**, as with the other mutun.

- [ ] **Step 1: Generate `arbaeen.txt` from the takw.in nodes**

Run this generator (it parses the already-downloaded HTML; each hadith = a `الحديث …` title node, body node(s) with `«…»`, and a takhrīj node matching رواه/أخرجه/متفق/حديث):

```bash
cd /Users/farhan/Developer/hifz-al-mutun-
python3 - <<'PY'
import re, html
t = open('/tmp/arbaeen.html', encoding='utf-8').read()
t = re.sub(r'<script.*?</script>','',t,flags=re.S)
t = re.sub(r'<style.*?</style>','',t,flags=re.S)
nodes = [html.unescape(n).strip() for n in re.findall(r'>([^<>]*[؀-ۿ][^<>]*)<', t)]
nodes = [n for n in nodes if n]

TITLE = re.compile(r'^الحديث\s')
TAKH  = re.compile(r'رواه|أخرجه|متفق|حديث\s+(حسن|صحيح)')

hadiths = []           # list of (title, body_lines[], takhrij)
cur = None
for n in nodes:
    if TITLE.match(n):
        cur = [n, [], ""]; hadiths.append(cur); continue
    if cur is None:     # pre-matn (titles, basmala) — skip
        continue
    if TAKH.search(n) and len(n) < 200:
        cur[2] = n.rstrip('.')
    else:
        cur[1].append(n)

# number them 1..N
header = '''# al-Arba'un al-Nawawiyya (40 Hadith of Imam al-Nawawi) — source transcription
# Prose matn (42 hadith) from takw.in's vocalised edition. The Prophet's words
# are wrapped in «…» (rendered in the subject colour); the rest is isnad. Each
# hadith's takhrij follows on a '=' line. VERIFY the Arabic text.
#
# File format (UTF-8):
#   '#' comment | '%' metadata | '@ n | title' hadith | body lines | '= takhrij'
#   «…» inside a body marks the Prophet's words (matn).

% id         = arbaeen
% title      = الأربعون النووية
% fullTitle  = الأربعون النووية
% titleLatin = al-Arba'un al-Nawawiyya
% author     = الإمام النووي
% subject    = hadith
% kind        = prose
'''
out = [header]
for i, (title, body, takh) in enumerate(hadiths, 1):
    out.append("")
    out.append(f"@ {i} | {title}")
    for line in body:
        out.append(line)
    if takh:
        out.append(f"= {takh}")
open('Tools/sources/arbaeen.txt', 'w', encoding='utf-8').write("\n".join(out) + "\n")
print(f"wrote Tools/sources/arbaeen.txt with {len(hadiths)} hadith")
PY
```

Expected: `wrote Tools/sources/arbaeen.txt with 42 hadith` (if the count differs, open the file and fix hadith boundaries by hand — the user will verify text regardless).

- [ ] **Step 2: Build the JSON**

Run:
```bash
cd /Users/farhan/Developer/hifz-al-mutun-
python3 Tools/build_matn.py Tools/sources/arbaeen.txt Resources/Content/arbaeen.json
python3 -c "import json;d=json.load(open('Resources/Content/arbaeen.json'));print('kind',d['kind'],'hadith',d['baytCount']);print('h1 title',d['hadiths'][0]['title']);print('h1 matn words',sum(1 for w in d['hadiths'][0]['body'] if w['role']=='matn'))"
```
Expected: `kind prose hadith 42`, a sensible h1 title, and ≥1 matn word in hadith 1.

- [ ] **Step 3: Confirm the bundled file loads through `ContentStore`**

Decoding is already unit-tested with inline JSON in Task 2 (`proseMatnDecodesAndPoemsStillDecode`). Here just confirm the **real bundled** `arbaeen.json` is discovered and parses, using the app's own loader. Open `Tests/MatchingTests/ContentStoreGroupingTests.swift` to copy its exact way of obtaining the loaded matns (it already exercises `ContentStore`), then add a test mirroring that pattern:

```swift
    @Test func arbaeenIsDiscoveredAsProse() throws {
        // Use the SAME ContentStore accessor ContentStoreGroupingTests uses.
        let all = ContentStore.shared.all            // ← match the real API
        let arbaeen = try #require(all.first { $0.id == "arbaeen" })
        #expect(arbaeen.kind == .prose)
        #expect(arbaeen.hadiths.count == 42)
        #expect(arbaeen.subject == .hadith)
    }
```

Replace `ContentStore.shared.all` with whatever accessor `ContentStoreGroupingTests` actually calls (e.g. a `ContentStore()` instance and its published `matns`). If `ContentStore` loads from the app bundle and the test can see it (the grouping test proves it can), this passes. The structural guarantees (42 hadith, roles) are already covered by the Python test in Step 2, so if the loader API is awkward, keep that as the authority and drop this test rather than inventing bundle plumbing.

- [ ] **Step 4: Build, deploy, and verify display on device**

Run the device build/deploy block from the conventions section, then launch:
```bash
xcrun devicectl device process launch --device 83FC1FDA-CF84-5FDB-8A23-BDEDA6BCD941 com.farhan.hifzalmutun
```
Manually confirm on the phone:
- A new cover appears on the **hadith** shelf (red), labelled الأربعون النووية, count "٤٢ حديثًا".
- Opening it shows the cover as page 0; swiping enters الحديث الأول with its heading, a justified paragraph, the Prophet's words in red, and the takhrīj small/dim at the foot.
- A long hadith (e.g. #2 Jibrīl, or the ḥalāl/ḥarām one) spills onto a second page; the next hadith starts on a fresh page.
- The index (الفهرس) lists all 42 and jumps correctly; the top-bar subtitle shows the current hadith.

- [ ] **Step 5: Commit**

```bash
git add Tools/sources/arbaeen.txt Resources/Content/arbaeen.json Tests/MatchingTests/ProseModelTests.swift
git commit -m "Content: al-Arba'un al-Nawawiyya (42 hadith, prose)"
```

---

## Final review (after all tasks)

Dispatch a code-reviewer over the whole change set, then:
- Confirm poems (Tuhfa, Jazariyyah, Shāṭibiyyah, Bayqūniyyah, Urjūza) are unchanged in the reader and on their shelves (regression).
- Confirm the prose reading font size (24pt, in `ProsePageView.fontSize` and `repaginateIfProse`) reads well on device; it is the one tunable knob — nudge both in lock-step if the user wants it bigger/smaller.
- User verifies the full Arabic text of the 42 hadith and the «…»/takhrīj boundaries.

## Notes for the implementer
- `ProsePageView.fontSize` (default 24) and the `fontSize` in `repaginateIfProse` **must stay equal** — measurement and rendering use the same size or pagination drifts.
- `.multilineTextAlignment(.leading)` + RTL environment gives a right-aligned Arabic paragraph; if true justified edges are wanted later, that's a follow-up (SwiftUI `Text` doesn't full-justify; a `UIViewRepresentable` over `UITextView` with `.justified` would be the path — out of scope here).
- Keep `baytCount` as the generic "unit count" (hadith count for prose); don't add a parallel `hadithCount` field.
