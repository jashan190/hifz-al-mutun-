# Prose Hadith Content Model — Design

**Status:** approved design (brainstorming) — ready for implementation plan

**Goal:** Add a prose content model so the 40 Hadith of al-Nawawī (الأربعون النووية, 42 hadith) can be read in the app, alongside the existing bayt/hemistich poems — without forking the reader, navigation, cover, or progress code.

**Scope (this spec):** Correct **display / read-only**. Each hadith flows across as many swipe-pages as it needs; the next hadith always starts on a fresh page. Prophet's words highlighted; takhrīj set apart; per-hadith headings; all 42 in the index; joins the hadith shelf.

**Explicitly deferred (future spec):** Memorize mode and recite-to-reveal voice for prose. The model here stores each word's normalised form so those can be added later without re-authoring the data or JSON.

**Tech:** SwiftUI (iOS 26), RTL, Swift Testing, XcodeGen (`project.yml` is source of truth), content pipeline `Tools/build_matn.py` → JSON in `Resources/Content/` → `Matn` model → auto-discovered by `ContentStore`.

---

## 1. Approach

**Extend the existing `Matn`** with a prose *kind* rather than building a parallel model/reader (chosen over a separate `ProseMatn` type, which would duplicate paging/navigation/progress/cover, and over shoehorning hadith into single-column bayts, which is semantically wrong and fights justified prose).

A prose `Matn` carries its hadith as **semantic units** (`[Hadith]`), *not* pre-paginated. Page breaks depend on font and screen, so a runtime **paginator** flows each hadith into `MatnPage`s when the reader opens. The result is an ordinary `pages: [MatnPage]` array, so the existing paged reader, folio numbers, index (`babs`), and reading-position save keep working unchanged.

---

## 2. Data model (`Core/Models/`)

### 2.1 Matn kind

Add to `Matn`:

```swift
enum MatnKind: String, Decodable, Hashable { case poem, prose }
```

`Matn` gains `let kind: MatnKind` (default `.poem` when absent, for all existing files). `baytsPerPage`/`baytCount`/`pageCount` stay for poems; for prose, `baytCount` is **repurposed as the hadith count** (so the cover's count label and any generic code keep working) — documented in the field comment. `Matn.pageCount` and `Matn.pages` stay 0/empty for prose (they are immutable `let`s); the true page list is produced at load by the paginator and held in the **reader's own state** (§5), never written back onto `Matn`.

### 2.2 Prose role

```swift
/// The part of a hadith a run of words belongs to, which decides its styling.
enum ProseRole: String, Decodable, Hashable {
    case isnad   // chain + narration frame — normal ink
    case matn    // the Prophet's words (the «…» spans) — subject colour
}
```

(Takhrīj is a separate field, below — not a role, since it is never part of the memorised/flowed body and is styled as a footer line.)

### 2.3 Prose word & hadith

```swift
/// A word in a hadith body: display text, normalised form (for future
/// matching), and the role that decides its colour.
struct ProseWord: Decodable, Hashable {
    let text: String
    let normalized: String
    let role: ProseRole
}

/// One hadith: its number, heading, the body as an ordered word sequence
/// (isnād + matn interleaved, each word role-tagged), and the takhrīj line.
struct Hadith: Decodable, Hashable, Identifiable {
    let number: Int
    let title: String        // e.g. "الحديث الأول"
    let body: [ProseWord]
    let takhrij: String      // e.g. "رواه البخاري ومسلم"
    var id: Int { number }
}
```

### 2.4 Page item for a prose fragment

A hadith can span pages, so a page holds a *fragment* of one hadith:

```swift
/// A page-sized slice of one hadith. `isFirst` → render the heading above it;
/// `isLast` → render the takhrīj below it. `words` is the slice for this page.
struct HadithFragment: Hashable {
    let hadithNumber: Int
    let title: String
    let words: [ProseWord]
    let takhrij: String
    let isFirst: Bool
    let isLast: Bool
}
```

Add a case to `PageItem`:

```swift
enum PageItem: Hashable {
    case heading(Heading)
    case bayt(Bayt)
    case hadith(HadithFragment)   // new
}
```

`PageItem` is only `Decodable` for `heading`/`bayt` (the on-disk poem schema). `.hadith` fragments are produced by the runtime paginator, never decoded, so `HadithFragment`/`PageItem.hadith` need no `Decodable` conformance. The existing `PageItem` decoder is untouched.

### 2.5 Matn storage of hadith

`Matn` gains `let hadiths: [Hadith]` (empty for poems). For prose, `Matn.pages` stays **empty**; the reader computes its page list via the paginator (§5) and reads from that. Convenience lookups (`bayts(onPage:)` etc.) are unaffected; add:

```swift
extension Matn {
    func hadithFragments(onPage n: Int) -> [HadithFragment] {
        items(onPage: n).compactMap { if case .hadith(let f) = $0 { return f } else { return nil } }
    }
}
```

---

## 3. On-disk JSON (schema)

Prose uses the **canonical (v2) direct `Matn` schema** (the branch in `Matn.init(from:)` that keys off `pages`), extended — *not* the legacy v1 path. The decoder adds:

- `kind: "prose"` (string; absent ⇒ `"poem"`).
- `hadiths: [...]` — array of `{ number, title, body: [{text, norm, role}], takhrij }`.
- `pages: []` (empty), `babs: []` (navigation built at load, see §6), `pageCount: 0`, `baytsPerPage: 0`, `baytCount: <hadith count>`.

The existing poem JSONs are unchanged (no `kind`, no `hadiths`). Decoding: in `Matn.init(from:)`, after the `pages`-present check, read `kind` (default poem) and `hadiths` (default `[]`). Because prose files *do* contain a `pages` key (empty array), they take the canonical branch, not the legacy `LegacyMatn` branch — confirm the guard is `c.contains(.pages)` (it is) and that an empty `pages` array is valid.

---

## 4. Source format & build pipeline (`Tools/`)

### 4.1 Source file `Tools/sources/arbaeen.txt`

Reuse the comment/metadata conventions. New line kinds for prose:

```
% id         = arbaeen
% title      = الأربعون النووية
% fullTitle  = الأربعون النووية
% titleLatin = al-Arba'un al-Nawawiyya
% author     = الإمام النووي
% subject    = hadith
% kind        = prose

@ 1 | الحديث الأول
عَنْ أَمِيرِ المُؤْمِنِينَ … قَالَ: «إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ …»
= رواه البخاري ومسلم

@ 2 | الحديث الثاني
…
```

- `@ <number> | <title>` starts a hadith.
- Body lines (plain lines after a `@`) are concatenated into the hadith body. **Text inside `«…»` guillemets is tagged `matn`; everything else is `isnad`.** Guillemets are stripped from the stored text (they are rendering cues, not content). Nested quotes inside an already-`matn` span stay `matn`.
- `= <text>` is the takhrīj line for the current hadith.

(The `% kind = prose` metadatum tells the builder to parse prose rather than `number<TAB>sadr<TAB>ajuz` bayts.)

### 4.2 Builder changes (`build_matn.py`)

Add a prose branch selected by `% kind = prose`:

- Parse `@`/body/`=` into hadith dicts.
- Tokenise each body into words honouring the `«…»` → `matn` spans; attach `normalize(word)` (reuse `Tools/normalize.py`) and the role per word.
- Emit the §3 JSON: `kind:"prose"`, `hadiths:[…]`, `pages:[]`, `babs:[]`, `baytsPerPage:0`, `pageCount:0`, `baytCount:<count>`.
- The existing poem branch is unchanged.

Validation: every hadith has a number, a non-empty title, non-empty body; numbers are contiguous from 1; warn (don't fail) if a hadith has no takhrīj.

### 4.3 Content source

The vocalised matn text comes from the takw.in edition already pulled (`/tmp/arbaeen.html`, basmala + 42 hadith with harakat, matn-only). Transcribe into `arbaeen.txt`, marking each hadith's Prophet-speech spans with `«…»` and its takhrīj with `=`. User verifies the text as with the other mutun.

---

## 5. Pagination (runtime) — `Features/Reader/ProsePaginator.swift`

A pure, testable function that turns `[Hadith]` + geometry into `[MatnPage]`:

```swift
struct ProsePaginator {
    /// Flow each hadith into page-sized fragments for the given content area and
    /// font. Each hadith starts a new page; a short hadith leaves its page
    /// partly empty; a long one spills onto further pages. Returns pages
    /// numbered 1…N with one or more `HadithFragment` items (always exactly one
    /// per page in this version) and the first-page map for navigation.
    static func paginate(_ hadiths: [Hadith],
                         contentSize: CGSize,
                         fontSize: CGFloat) -> (pages: [MatnPage], firstPageOf: [Int: Int])
}
```

Algorithm per hadith:
1. Measure the heading height (first page only) and the takhrīj height (last page only) as fixed blocks.
2. Greedily grow a word slice, measuring the wrapped height of the body text for the content width using **TextKit** (`NSAttributedString.boundingRect(with:options:.usesLineFragmentOrigin)` with the page font). When adding the next word would exceed the available body height, close the page and start the next.
3. The first fragment carries `isFirst=true` (reserve heading height); the final fragment of the hadith carries `isLast=true` (reserve takhrīj height). A single-page hadith has both true.
4. Never pack two hadith on one page — the next hadith always begins a new `MatnPage`.

Measurement uses the same font the view renders with (a single `PageFont`-based attributed string helper, shared so measurement == layout). Fixed comfortable reading size (see §9); prose does **not** auto-shrink like the fitted poems.

**Where it runs:** `PageScreen` already has the page geometry. For a prose `matn`, it computes `pages` via the paginator in an `onGeometryChange`/`task` keyed by `(contentSize, fontSize)`, stores them in `@State`, and feeds the existing `TabView`. Poems keep using `matn.pages` directly. A tiny seam: a computed `pages` the reader reads from (prose) vs `matn.pages` (poem).

Re-pagination on size change is expected and acceptable (page count and the saved page index may shift when the system text size changes).

---

## 6. Navigation / index

Each hadith becomes **one index entry**, reusing the existing `Bab`/sidecar machinery:

- After pagination, build `babs = hadiths.map { Bab(id: "h\($0.number)", title: $0.title, startPage: firstPageOf[$0.number]!) }`.
- The sidecar "الفهرس/الأبواب" list (already hidden when `babs.isEmpty`) shows all 42 → tapping jumps to the hadith's first page.
- The top-bar subtitle (`babsCaption = currentBab(onPage:)?.title`) shows the current hadith's title.
- The type-to-jump control keeps working by page number.

Because `babs` for prose is built at load (post-pagination), it lives on the reader's computed state next to `pages`, not in the JSON.

---

## 7. Rendering — `Features/Reader/ProsePageView.swift`

A new view for `PageItem.hadith(fragment)`, used by `PageView` when it encounters the `.hadith` case (poem cases unchanged):

- **Heading** (if `isFirst`): the hadith title (`DisplayFont`, subject colour), centred.
- **Body:** a single full-width, **justified** RTL paragraph built from the fragment's `words`. `isnad` words in `Theme.ink`; `matn` words in `matn.subject.accent`. Built as one `Text`/`AttributedString` so wrapping and justification are natural (no per-word layout). Justification via `.multilineTextAlignment` + line-break/justify configuration consistent with the app's Arabic text.
- **Takhrīj** (if `isLast`): the takhrīj string, smaller and dimmed (`Theme.ink.opacity(~0.6)` / caption size), set apart from the body.
- **Folio:** running page number (reuse the existing `folio`).
- Background `Theme.cover`, same margins as poem pages.

The cover-as-first-page (`startOnCover`) and hero-zoom behaviour are unchanged — the prose reader is still `PageScreen`, which already handles the cover at tag 0.

---

## 8. Cover (`Features/Library/MatnCover.swift`)

- Prose matns render the normal manuscript cover, **hadith subject** (red) → hadith shelf, red outline/chrome.
- The count label is currently "`\(baytCount) بيت`". Make the unit **kind-aware**: `matn.kind == .prose ? "\(count) حديثًا" : "\(count) بيت"` (count = `baytCount`, repurposed as hadith count for prose). The `cartLabel` ("منظومة"/"متن") becomes "أربعون"/"حديث" for prose (small refinement; pick "الأربعون" cartouche label).

---

## 9. Open parameter

- **Prose reading font size:** pick a comfortable fixed default (starting point ~ the poem `referenceSize` range, e.g. 22–26pt for the body, heading larger). Tunable on device after first display. Measurement and layout must use the same value.

---

## 10. Testing (Swift Testing)

- **Builder:** a fixture `arbaeen`-style source → assert hadith count, titles, contiguous numbers, correct `matn`/`isnad` role tagging around `«…»`, takhrīj captured, normalised forms present.
- **Decoding:** a small prose JSON → `Matn` with `kind == .prose`, hadiths populated, `pages`/`babs` empty, `baytCount == hadithCount`. Confirm existing poem JSONs still decode as `.poem` (regression).
- **Paginator (pure function):**
  - A short hadith → exactly one page, fragment `isFirst && isLast`.
  - A long hadith (synthetic long body) → ≥2 pages; only the first has the heading, only the last has the takhrīj; words partition exactly (no loss/dup, order preserved).
  - Two hadith → the second's first fragment starts a new page (no shared page).
  - `firstPageOf` maps every hadith to the page its first fragment is on.
- **Navigation:** built `babs` have one entry per hadith with `startPage == firstPageOf[n]`.

Measurement-dependent exact page counts are not asserted against device metrics; paginator tests inject a stub/known measurement so they're deterministic (the measure step is a closure parameter, defaulting to the TextKit implementation).

---

## 11. Out of scope / future

- Memorize mode + recite-to-reveal for prose (model is ready: `ProseWord.normalized` + word order).
- Per-word colouring beyond isnād/matn (e.g. highlighting a narrator's name).
- Any change to poem rendering or the poem JSONs.

---

## 12. File map

- **Modify:** `Core/Models/Matn.swift` (kind, hadiths, ProseRole/ProseWord/Hadith/HadithFragment, `.hadith` PageItem case + lookup, decoder), `Tools/build_matn.py` (prose branch), `Features/Reader/PageView.swift` (render `.hadith`), `Features/Reader/PageScreen.swift` (prose pages via paginator + built babs), `Features/Library/MatnCover.swift` (kind-aware count/label).
- **Create:** `Tools/sources/arbaeen.txt`, `Resources/Content/arbaeen.json`, `Features/Reader/ProsePaginator.swift`, `Features/Reader/ProsePageView.swift`, tests under the project's test target.
