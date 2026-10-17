import Foundation

/// Which letters of a written word to show as the mistake, given what was
/// heard: each differing letter with its harakat, as scalar ranges of the
/// written word, so the reciter sees the right letter and vowels there.
enum LetterEmphasis {
    static func ranges(written: String, heard: String) -> [Range<Int>] {
        let letters = ArabicNormalize.letterRanges(written)
        let differing = mismatchedLetters(expected: ArabicNormalize.normalize(written),
                                          heard: ArabicNormalize.normalize(heard))
        return differing.sorted().compactMap { letters.indices.contains($0) ? letters[$0] : nil }
    }
}
