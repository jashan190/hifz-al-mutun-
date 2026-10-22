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
    /// Flagged words for a matn, in reading order. Orphan/out-of-range keys are skipped.
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
            if let existing = map[key], existing.added, !m.added { map[key] = m }
            else if map[key] == nil { map[key] = m }
        }
        return map
    }
}
