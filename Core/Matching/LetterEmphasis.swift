import Foundation

/// Which letters of a written word to show as the mistake, given what was
/// heard: each differing letter with its harakat, as scalar ranges of the
/// written word, so the reciter sees the right letter and vowels there.
enum LetterEmphasis {
    static func ranges(written: String, heard: String) -> [Range<Int>] {
        let letters = ArabicNormalize.letterRanges(written)
        let expected = ArabicNormalize.normalize(written), said = ArabicNormalize.normalize(heard)
        if expected == said { return vowelRanges(written: written, heard: heard, letters: letters) }
        let differing = mismatchedLetters(expected: expected, heard: said)
        return differing.sorted().compactMap { letters.indices.contains($0) ? letters[$0] : nil }
    }

    /// The same letters with other harakat (the vowel check writes what was
    /// said with the vowel changed): the letters whose marks differ.
    private static func vowelRanges(written: String, heard: String, letters: [Range<Int>]) -> [Range<Int>] {
        let heardLetters = ArabicNormalize.letterRanges(heard)
        guard heardLetters.count == letters.count else { return [] }
        let a = Array(written.unicodeScalars), b = Array(heard.unicodeScalars)
        return zip(letters, heardLetters).compactMap { mine, theirs in
            a[mine].elementsEqual(b[theirs]) ? nil : mine
        }
    }
}
