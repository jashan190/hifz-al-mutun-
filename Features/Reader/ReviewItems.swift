import Foundation

/// One row of the cumulative review: a flagged word, where it is, and the text.
struct ReviewItem: Identifiable {
    let key: FlagKey
    let word: String        // the flagged word, as written
    let location: String    // "Bayt 12 · first half" / "الحديث ٣"
    /// Every flagged word the row stands for: one, or a whole bayt's.
    let keys: [FlagKey]
    var id: FlagKey { key }

    init(key: FlagKey, word: String, location: String, keys: [FlagKey]? = nil) {
        self.key = key
        self.word = word
        self.location = location
        self.keys = keys ?? [key]
    }
}

/// Resolves a matn's flagged positions into display rows, and builds the
/// (ephemeral) "you said X" annotation map from a sitting's summary.
enum ReviewItems {
    /// Reading-order key: bayt, then sadr before ajuz, then word position.
    private static func sortKey(_ k: FlagKey) -> (Int, Int, Int) {
        (k.bayt, k.half == .sadr ? 0 : 1, k.wordIndex)
    }

    /// Flagged words for a matn, in reading order. Orphan/out-of-range keys are
    /// skipped. A bayt with every word flagged is one row: "skipped" if the
    /// current sitting left it out (`skippedBayts`), else "whole bayt".
    static func resolve(matn: Matn, flags: Set<FlagKey>, skippedBayts: Set<Int> = []) -> [ReviewItem] {
        let sorted = flags.sorted { sortKey($0) < sortKey($1) }
        var items: [ReviewItem] = []
        for key in sorted {
            if let bayt = wholeBayt(matn: matn, key.bayt, flags: flags) {
                if items.last?.key.bayt == key.bayt, items.last?.keys.count ?? 0 > 1 { continue }
                items.append(ReviewItem(key: key, word: bayt.sadr.text + " … " + bayt.ajuz.text,
                                        location: "Bayt \(key.bayt) · \(skippedBayts.contains(key.bayt) ? "skipped" : "whole bayt")",
                                        keys: wholeKeys(bayt)))
                continue
            }
            guard let word = word(matn: matn, key: key) else { continue }
            items.append(ReviewItem(key: key, word: word, location: location(matn: matn, key: key)))
        }
        return items
    }

    /// The bayt, if every one of its words is flagged: those with letters, as
    /// the tracker judges no others.
    private static func wholeBayt(matn: Matn, _ number: Int, flags: Set<FlagKey>) -> Bayt? {
        guard matn.kind != .prose else { return nil }
        for page in matn.pages {
            for item in page.items {
                guard case .bayt(let b) = item, b.number == number else { continue }
                let keys = wholeKeys(b).filter { key in
                    let half = key.half == .sadr ? b.sadr : b.ajuz
                    return !ArabicNormalize.normalize(half.words[key.wordIndex].text).isEmpty
                }
                return keys.count > 1 && keys.allSatisfy(flags.contains) ? b : nil
            }
        }
        return nil
    }

    private static func wholeKeys(_ b: Bayt) -> [FlagKey] {
        b.sadr.words.indices.map { FlagKey(bayt: b.number, half: .sadr, wordIndex: $0) }
            + b.ajuz.words.indices.map { FlagKey(bayt: b.number, half: .ajuz, wordIndex: $0) }
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
