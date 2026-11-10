import Foundation

/// Idgham: a word ending in tanween or noon sakina runs into a next word
/// starting with ي ر م ل و ن, so the same text is said two ways, and Whisper
/// spells each its own way. Both are right: this lists the spellings.
enum Idgham {
    private static let letters: Set<Character> = ["ي", "ر", "م", "ل", "و", "ن"]

    /// Each word that can merge into the next one, by flat index: how it may
    /// be spelled when said with or without idgham, as (normalized) spellings.
    /// `written` and `words` are parallel; words with nothing to say are passed over.
    static func spellings(written: [String], words: [String]) -> [Int: [String]] {
        var found: [Int: [String]] = [:]
        var next: Int?
        for i in words.indices.reversed() where !words[i].isEmpty {
            if let next, let forms = forms(written: written[i], word: words[i], next: words[next]) { found[i] = forms }
            next = i
        }
        return found
    }

    /// The word's spellings before `next`: its ending kept, dropped (merged
    /// away), or written as the noon it's said with. Nil if it can't merge.
    static func forms(written: String, word: String, next: String) -> [String]? {
        guard let first = next.first, letters.contains(first), let last = word.last else { return nil }
        let scalars = Array(written.unicodeScalars)
        let ranges = ArabicNormalize.letterRanges(written)
        guard ranges.count == word.count, let end = ranges.last else { return nil }
        func marks(_ r: Range<Int>) -> [UInt32] { scalars[r].dropFirst().map(\.value) }
        let isTanween = { (m: UInt32) in (0x064B...0x064D).contains(m) }
        if last == "ن", marks(end).allSatisfy({ $0 == 0x0652 }) {   // noon with a sukun (or unmarked)
            return word.count > 1 ? [word, String(word.dropLast())] : nil
        }
        var stem = word
        if marks(end).contains(where: isTanween) {
            if last == "ا" { stem.removeLast() }                    // its alif, marked: ـاً
        } else if ranges.count >= 2, last == "ا" || last == "ي",
                  marks(ranges[ranges.count - 2]).contains(where: isTanween) {
            stem.removeLast()                                       // its alif or ى: ـًا ـًى
        } else {
            return nil
        }
        var forms = [word, stem, stem + "ن"]
        if scalars[end.lowerBound].value == 0x0629 {                // ة said as ت
            let said = String(stem.dropLast()) + "ت"
            forms += [said, said + "ن"]
        }
        return Array(Set(forms)).sorted()
    }
}
