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
    private let baytStart: [Int: Int]   // bayt number → first flat word index

    init(matn: Matn) {
        var words: [String] = []
        var refs: [WordRef] = []
        var pageStart: [Int: Int] = [:]
        var baytStart: [Int: Int] = [:]
        for page in matn.pages {
            pageStart[page.page] = words.count
            for item in page.items {
                guard case .bayt(let bayt) = item else { continue }
                baytStart[bayt.number] = words.count
                for (half, hemi) in [(Half.sadr, bayt.sadr), (Half.ajuz, bayt.ajuz)] {
                    for (wi, word) in hemi.words.enumerated() {
                        // Normalize at runtime with the same function the tracker
                        // applies to recognizer output, so both sides always agree
                        // (the stored forms can differ, e.g. keeping ئ/ؤ).
                        words.append(ArabicNormalize.normalize(word.text))
                        refs.append(WordRef(page: page.page, bayt: bayt.number,
                                            half: half, wordIndex: wi))
                    }
                }
            }
        }
        self.normalizedWords = words
        self.refs = refs
        self.pageStart = pageStart
        self.baytStart = baytStart
    }

    /// Flat index of the first word on a page; `normalizedWords.count` if the
    /// page has no words at or after it (clamps callers to the end). A
    /// heading-only page (no bayts) reports the first word of the next
    /// word-bearing page — the right seed for "start reciting from this page".
    /// Flat index of a bayt's first word, or nil for an unknown bayt.
    func firstWordIndex(ofBayt bayt: Int) -> Int? { baytStart[bayt] }

    func firstWordIndex(onPage page: Int) -> Int {
        if let start = pageStart[page] { return start }
        // Page not found (e.g. out of range): clamp to end.
        return normalizedWords.count
    }
}
