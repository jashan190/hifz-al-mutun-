import Foundation

/// Finds harakat mistakes: lines up the phonemes expected for some words with
/// the phonemes the model heard, and reports each short vowel (fatha, damma,
/// kasra) heard as another one.
///
/// Only swaps are reported. A vowel not heard at all is usually the reciter
/// pausing (waqf drops it), and the length of madd and ghunna varies with
/// the reciter, so neither counts.
enum VowelJudge {
    struct Slip: Equatable {
        /// Which of the given words, and which of its short vowels (0-based).
        let word: Int
        let vowel: Int
        let expected: Unicode.Scalar
        let heard: Unicode.Scalar
    }

    static let fatha = Unicode.Scalar(0x064E)!, damma = Unicode.Scalar(0x064F)!, kasra = Unicode.Scalar(0x0650)!
    static func isShortVowel(_ s: Unicode.Scalar) -> Bool { s == fatha || s == damma || s == kasra }

    /// `expected` holds each word's phonemes, in order; `heard` is the model's
    /// output for audio that holds these words, possibly with a little of the
    /// words before and after at its edges, which cost nothing here.
    static func slips(expected: [String], heard: String) -> [Slip] {
        var ref: [Unicode.Scalar] = []
        var owner: [(word: Int, vowel: Int?)] = []
        for (w, word) in expected.enumerated() {
            var vowels = 0
            for s in word.unicodeScalars {
                ref.append(s)
                if isShortVowel(s) { owner.append((w, vowels)); vowels += 1 } else { owner.append((w, nil)) }
            }
        }
        let hyp = Array(heard.unicodeScalars)
        guard !ref.isEmpty, !hyp.isEmpty else { return [] }

        // Edit distance with the heard text's ends free: d[i][j] is the cost
        // of ref[..<i] against heard text ending at j.
        let n = ref.count, m = hyp.count
        var d = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { d[i][0] = i }
        for i in 1...n {
            for j in 1...m {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                              d[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1))
            }
        }
        var j = (0...m).min { d[n][$0] < d[n][$1] }!
        var i = n
        var found: [Slip] = []
        while i > 0 {
            if j > 0, d[i][j] == d[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1) {
                let a = ref[i - 1], b = hyp[j - 1]
                if a != b, isShortVowel(a), isShortVowel(b), let vowel = owner[i - 1].vowel {
                    found.append(Slip(word: owner[i - 1].word, vowel: vowel, expected: a, heard: b))
                }
                i -= 1; j -= 1
            } else if d[i][j] == d[i - 1][j] + 1 {
                i -= 1
            } else {
                j -= 1
            }
        }
        return found.reversed()
    }

    /// The written word as it was said: its `vowel`-th short vowel (a tanween
    /// counts, as the phonemes write it as a vowel and a nun) changed to
    /// `heard`. nil when the written word doesn't carry the same number of
    /// short vowels as its phonemes, so the slip can't be placed on a letter
    /// (e.g. اللهِ, whose lam's fatha isn't written).
    static func written(_ word: String, phonemes: String, vowel: Int, heard: Unicode.Scalar) -> String? {
        let tanween: [UInt32: Unicode.Scalar] = [0x064E: "\u{064B}", 0x064F: "\u{064C}", 0x0650: "\u{064D}"]
        func isWrittenVowel(_ s: Unicode.Scalar) -> Bool { (0x064B...0x0650).contains(s.value) }
        var scalars = Array(word.unicodeScalars)
        let marks = scalars.indices.filter { isWrittenVowel(scalars[$0]) }
        guard marks.count == phonemes.unicodeScalars.filter(isShortVowel).count, marks.indices.contains(vowel)
        else { return nil }
        let at = marks[vowel]
        scalars[at] = (0x064B...0x064D).contains(scalars[at].value) ? tanween[heard.value]! : heard
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }
}
