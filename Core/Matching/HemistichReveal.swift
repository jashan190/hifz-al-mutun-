import Foundation

/// Slices a hemistich's display `segments` to just the first `k` words, so the
/// Memorize reveal can show recited words with their real colours and leave the
/// rest blank. Operates on unicode scalars so a cut never splits a grapheme.
///
/// Relies on the content invariant that a hemistich's `segments` text (text
/// runs only) concatenates exactly to its `text`, and that `words` are the
/// space-separated tokens of `text` that contain letters. Punctuation-only
/// tokens (the book's "-" and "،") sit in `text` but aren't words.
enum HemistichReveal {
    static func prefix(_ hemistich: Hemistich, words k: Int) -> [Segment] {
        if k <= 0 { return [] }
        if k >= hemistich.words.count { return hemistich.segments }

        let cut = scalarEnd(ofWord: k, in: hemistich.text)

        var result: [Segment] = []
        var consumed = 0
        for seg in hemistich.segments {
            guard let text = seg.text else {
                // Footnote marker: keep it only if it sits within the revealed span.
                if consumed < cut { result.append(seg) }
                continue
            }
            let len = text.unicodeScalars.count
            if consumed + len <= cut {
                result.append(seg)
                consumed += len
            } else if consumed < cut {
                let take = cut - consumed
                let piece = String(String.UnicodeScalarView(text.unicodeScalars.prefix(take)))
                result.append(Segment(text: piece, color: seg.color, footnote: nil))
                break
            } else {
                break
            }
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
