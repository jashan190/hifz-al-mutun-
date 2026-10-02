import Foundation

// Decoding for the older content schema (v1) produced by Tools/build_matn.py —
// used by Tuhfa and Jazariyyah. It models a matn as a flat bayt list with
// computed page/row, bab ranges, and per-word colour (optionally per-letter
// `runs`). We decode it, then map it to the canonical `Matn` so the rest of the
// app only ever sees one model. The on-disk v1 files are left untouched.

struct LegacyMatn: Decodable {
    let id: String
    let title: String
    let fullTitle: String?
    let titleLatin: String
    let author: String
    let meter: String
    let baytsPerPage: Int
    let pageCount: Int
    let baytCount: Int
    let babs: [LegacyBab]
    let bayts: [LegacyBayt]
}

struct LegacyBab: Decodable {
    let id: String
    let title: String
    let startBayt: Int
    let endBayt: Int
}

struct LegacyBayt: Decodable {
    let number: Int
    let page: Int
    let babId: String
    let sadr: String
    let ajuz: String
    let sadrWords: [LegacyWord]
    let ajuzWords: [LegacyWord]
}

struct LegacyWord: Decodable {
    let text: String
    let norm: String
    let color: String?
    let runs: [LegacyRun]?
}

struct LegacyRun: Decodable {
    let text: String
    let color: String?
}

private func segColor(_ raw: String?) -> SegmentColor {
    switch raw {
    case "red": return .red
    case "blue": return .blue
    default: return .black
    }
}

extension LegacyWord {
    /// This word as coloured pieces: its `runs` if present (per-letter colour),
    /// else the whole word in its single colour.
    var pieces: [(text: String, color: SegmentColor)] {
        if let runs, !runs.isEmpty {
            return runs.map { ($0.text, segColor($0.color)) }
        }
        return [(text, segColor(color))]
    }
}

extension LegacyBayt {
    private func hemistich(_ words: [LegacyWord]) -> Hemistich {
        var segments: [Segment] = []
        for (i, w) in words.enumerated() {
            if i > 0 { segments.append(Segment(text: " ", color: .black, footnote: nil)) }
            for piece in w.pieces {
                segments.append(Segment(text: piece.text, color: piece.color, footnote: nil))
            }
        }
        let text = segments.compactMap(\.text).joined()
        let out = words.map { Word(text: $0.text, normalized: $0.norm) }
        return Hemistich(text: text, segments: segments, words: out)
    }

    var canonicalSadr: Hemistich { hemistich(sadrWords) }
    var canonicalAjuz: Hemistich { hemistich(ajuzWords) }
}

extension LegacyMatn {
    /// Convert the legacy shape into the canonical `Matn`: group bayts into pages
    /// and insert a heading before the bayt that starts each bab.
    func canonical() -> Matn {
        let byStart = Dictionary(grouping: babs, by: \.startBayt)
        let babTitle = Dictionary(uniqueKeysWithValues: babs.map { ($0.id, $0.title) })

        var pages: [MatnPage] = []
        for pageNo in 1...max(1, pageCount) {
            let onPage = bayts.filter { $0.page == pageNo }.sorted { $0.number < $1.number }
            var items: [PageItem] = []
            for b in onPage {
                if let starting = byStart[b.number] {
                    for bab in starting {
                        items.append(.heading(Heading(
                            text: bab.title,
                            segments: [Segment(text: bab.title, color: .black, footnote: nil)]
                        )))
                    }
                }
                items.append(.bayt(Bayt(number: b.number, sadr: b.canonicalSadr, ajuz: b.canonicalAjuz)))
            }
            pages.append(MatnPage(page: pageNo, items: items))
        }

        let canonicalBabs = babs
            .sorted { $0.startBayt < $1.startBayt }
            .map { Bab(id: $0.id, title: $0.title, startPage: (($0.startBayt - 1) / baytsPerPage) + 1) }

        _ = babTitle   // (kept for clarity; titles are read from babs directly)

        return Matn(
            id: id, title: title, fullTitle: fullTitle, titleLatin: titleLatin,
            author: author, meter: meter,
            baytsPerPage: baytsPerPage, pageCount: pageCount, baytCount: baytCount,
            pages: pages, babs: canonicalBabs, reviewNotes: []
        )
    }
}
