import Foundation

// MARK: - Read-only content models (canonical schema v2)
//
// A matn is a list of printed pages. Each page holds items in print order:
// headings and bayts interleaved exactly as they sit on the page. A bayt is one
// row (sadr on the right, ajuz on the left); each half-line carries coloured
// `segments` (for display) and a `words` list (for voice matching / recall).
//
// Two on-disk schemas decode into this model:
//   • v2 (ash-Shatibiyyah, Suwaid edition): the canonical shape below, loaded
//     straight from the file — pages, items and headings are taken as given.
//   • v1 (Tuhfa, Jazariyyah from build_matn.py): the older bab-range + per-word
//     shape, converted to canonical in memory so the rest of the app sees one
//     model. See `LegacyMatn` at the bottom.
//
// IMPORTANT: this is read-only content. A user's progress and marks live
// separately in SwiftData and reference bayts by (matnID, baytNumber).

/// The colour a run of text is printed in.
enum SegmentColor: String, Decodable, Hashable {
    case black   // the poet's words
    case blue    // Quranic words (and, in a few chapters, letter lists / terms)
    case red     // rumuz (code letters), the separating wāw, reader names, emphasis
}

/// One run of a half-line: either coloured text, or a footnote marker. Segments
/// of a half-line concatenate (text runs only) to its plain `text`. A run can be
/// a single letter inside a word, so a half-line is drawn as one AttributedString
/// or Arabic letter-joining breaks.
struct Segment: Decodable, Hashable {
    let text: String?          // the run's text; nil when this is a footnote marker
    let color: SegmentColor?   // nil treated as black
    let footnote: String?      // eastern-digit marker (e.g. "٤٥"); nil for text runs
}

/// A plain word with its normalized (match-only) form. The normalized form has
/// harakat and marks stripped, alif forms unified, ى→ي and ة→ه. The order and
/// splitting line up with the words as displayed, so a recall/voice layer can be
/// built from the same split.
struct Word: Decodable, Hashable {
    let text: String
    let normalized: String
}

/// One half-line: the plain text (for width measuring), its coloured segments
/// (for display) and its words (for matching).
struct Hemistich: Decodable, Hashable {
    let text: String
    let segments: [Segment]
    let words: [Word]
}

/// A centred heading that sits between rows: a bab or surah title, the basmala,
/// or the closing line. Carries its own segments (usually black, sometimes with
/// blue/red parts).
struct Heading: Decodable, Hashable {
    let text: String
    let segments: [Segment]
}

/// One line of verse: a sadr (first hemistich, on the right) and ajuz (second,
/// on the left), with its continuous 1-based number.
struct Bayt: Decodable, Hashable, Identifiable {
    let number: Int
    let sadr: Hemistich
    let ajuz: Hemistich

    var id: Int { number }

    enum CodingKeys: String, CodingKey { case number = "n", sadr, ajuz }
}

/// An item in a page's print order.
enum PageItem: Hashable {
    case heading(Heading)
    case bayt(Bayt)
    case hadith(HadithFragment)   // produced by ProsePaginator, never decoded
}

extension PageItem: Decodable {
    private enum Keys: String, CodingKey { case type }
    private enum Kind: String, Decodable { case heading, bayt }

    init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Keys.self).decode(Kind.self, forKey: .type)
        switch kind {
        case .heading: self = .heading(try Heading(from: decoder))
        case .bayt:    self = .bayt(try Bayt(from: decoder))
        }
    }
}

/// One printed page: its number and its items in print order.
struct MatnPage: Decodable, Hashable {
    let page: Int
    let items: [PageItem]
}

/// A navigable heading for the index: its title and the page it starts on.
struct Bab: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let startPage: Int
}

/// A spot the transcriber left open after proofreading. Debug-only; never shown.
struct ReviewNote: Decodable, Hashable {
    let page: Int
    let n: Int
    let notes: [String]
}

/// A whole matn: metadata, every page in print order, the heading index, and the
/// (debug-only) review notes. May be a poem (bayts) or prose (hadiths).
struct Matn: Hashable, Identifiable {
    let id: String
    let title: String          // common / nickname title, shown prominently
    let fullTitle: String?     // the real/full title, shown as a subtitle
    let titleLatin: String
    let author: String
    let meter: String
    let subject: Subject
    let kind: MatnKind            // poem (bayts) or prose (hadith)
    let hadiths: [Hadith]         // prose only; empty for poems
    let baytsPerPage: Int
    let pageCount: Int
    let baytCount: Int            // for prose, repurposed as hadith count
    let pages: [MatnPage]
    let babs: [Bab]
    let reviewNotes: [ReviewNote]
}

// MARK: - Decoding (canonical v2 directly; legacy v1 via conversion)

extension Matn: Decodable {
    private enum Keys: String, CodingKey {
        case schemaVersion, id, title, fullTitle, titleLatin, author, meter, subject
        case kind, hadiths
        case baytsPerPage, pageCount, baytCount, pages, babs, reviewNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard c.contains(.pages) else {
            // Older per-word / bab-range file: decode and convert.
            self = try LegacyMatn(from: decoder).canonical()
            return
        }
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        fullTitle = try c.decodeIfPresent(String.self, forKey: .fullTitle)
        titleLatin = try c.decode(String.self, forKey: .titleLatin)
        author = try c.decode(String.self, forKey: .author)
        meter = try c.decode(String.self, forKey: .meter)
        subject = Subject.from(id: try c.decodeIfPresent(String.self, forKey: .subject))
        kind = try c.decodeIfPresent(MatnKind.self, forKey: .kind) ?? .poem
        hadiths = try c.decodeIfPresent([Hadith].self, forKey: .hadiths) ?? []
        baytsPerPage = try c.decode(Int.self, forKey: .baytsPerPage)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        baytCount = try c.decode(Int.self, forKey: .baytCount)
        pages = try c.decode([MatnPage].self, forKey: .pages)
        babs = try c.decode([Bab].self, forKey: .babs)
        reviewNotes = try c.decodeIfPresent([ReviewNote].self, forKey: .reviewNotes) ?? []
    }
}

// MARK: - Convenience lookups

extension Matn {
    /// The page with a given 1-based number.
    func page(_ n: Int) -> MatnPage? { pages.first { $0.page == n } }

    /// Items (headings + bayts) on a page, in print order.
    func items(onPage n: Int) -> [PageItem] { page(n)?.items ?? [] }

    /// The bayts on a page, in order.
    func bayts(onPage n: Int) -> [Bayt] {
        items(onPage: n).compactMap { if case .bayt(let b) = $0 { return b } else { return nil } }
    }

    /// The hadith fragments on a page (prose), in order.
    func hadithFragments(onPage n: Int) -> [HadithFragment] {
        items(onPage: n).compactMap {
            if case .hadith(let f) = $0 { return f } else { return nil }
        }
    }

    /// The chapter/section active on a page: the last heading at or before it.
    func currentBab(onPage n: Int) -> Bab? { babs.last { $0.startPage <= n } }

    /// The 1-based page a bayt number falls on.
    func page(ofBayt bayt: Int) -> Int { (bayt - 1) / baytsPerPage + 1 }
}
