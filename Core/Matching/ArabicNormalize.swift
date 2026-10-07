import Foundation

/// Runtime port of `Tools/normalize.py`. Produces the match-only form used to
/// line recognizer output up with the stored `Word.normalized`. Keep in sync
/// with the Python rules: strip marks + tatweel, fold أإآٱ→ا, ى→ي, ة→ه, then
/// keep only Arabic letters (U+0621–063A, U+0641–064A).
enum ArabicNormalize {
    private static func isMark(_ v: UInt32) -> Bool {
        (0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v) ||
        v == 0x0670 || (0x06D6...0x06DC).contains(v) ||
        (0x06DF...0x06E8).contains(v) || (0x06EA...0x06ED).contains(v)
    }
    private static func isKeptLetter(_ v: UInt32) -> Bool {
        (0x0621...0x063A).contains(v) || (0x0641...0x064A).contains(v)
    }
    private static func fold(_ s: Unicode.Scalar) -> Unicode.Scalar {
        switch s.value {
        case 0x0623, 0x0625, 0x0622, 0x0671: return Unicode.Scalar(0x0627)! // أإآٱ → ا
        case 0x0649: return Unicode.Scalar(0x064A)!                          // ى → ي
        case 0x0629: return Unicode.Scalar(0x0647)!                          // ة → ه
        default: return s
        }
    }

    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        // Compatibility decomposition so composed forms split predictably: e.g.
        // آ → ا + maddah (U+0653), whose mark is then stripped by isMark below.
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            if isMark(scalar.value) { continue }
            if scalar.value == 0x0640 { continue }   // tatweel
            let folded = fold(scalar)
            if isKeptLetter(folded.value) { out.append(folded) }
        }
        return String(out)
    }
}
