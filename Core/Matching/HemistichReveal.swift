import Foundation

/// Slices a hemistich's display `segments` to a run of its words, so Memorize
/// can draw each recited word on its own with its real colours. Operates on
/// unicode scalars so a cut never splits a grapheme.
///
/// Relies on the content invariant that a hemistich's `segments` text (text
/// runs only) concatenates exactly to its `text`, and that `words` are the
/// space-separated tokens of `text` that contain letters. Punctuation-only
/// tokens (the book's "-" and "،") sit in `text` but aren't words; one belongs
/// to the word after it.
enum HemistichReveal {
    /// The segments for `words` (0-based, half-open). A footnote marker goes
    /// with the word it follows.
    static func span(_ hemistich: Hemistich, words: Range<Int>) -> [Segment] {
        let count = hemistich.words.count
        let lower = max(0, words.lowerBound), upper = min(count, words.upperBound)
        guard lower < upper else { return [] }

        let total = hemistich.text.unicodeScalars.count
        let prevEnd = lower == 0 ? -1 : scalarEnd(ofWord: lower, in: hemistich.text)
        let from = lower == 0 ? 0 : prevEnd + 1               // past the space
        let to = upper == count ? total : scalarEnd(ofWord: upper, in: hemistich.text)

        var result: [Segment] = []
        var consumed = 0
        for seg in hemistich.segments {
            guard let text = seg.text else {
                if consumed > prevEnd && consumed <= to { result.append(seg) }
                continue
            }
            let len = text.unicodeScalars.count
            let a = max(from, consumed), b = min(to, consumed + len)
            if a < b {
                let scalars = text.unicodeScalars
                let lo = scalars.index(scalars.startIndex, offsetBy: a - consumed)
                let hi = scalars.index(scalars.startIndex, offsetBy: b - consumed)
                result.append(Segment(text: String(scalars[lo..<hi]), color: seg.color, footnote: nil))
            }
            consumed += len
        }
        return result
    }

    /// Scalar offset in `text` just past the `k`-th (1-based) word token.
    static func scalarEnd(ofWord k: Int, in text: String) -> Int {
        var offset = 0
        var seen = 0
        for token in text.split(separator: " ", omittingEmptySubsequences: false) {
            offset += token.unicodeScalars.count
            if !ArabicNormalize.normalize(String(token)).isEmpty {
                seen += 1
                if seen == k { return offset }
            }
            offset += 1   // the separating space
        }
        return text.unicodeScalars.count
    }
}
