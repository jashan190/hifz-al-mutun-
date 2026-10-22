import SwiftUI

/// Builds the display text for a hadith body: a single string so wrapping and
/// justification are natural, with each word coloured by its role.
enum ProseText {
    /// Plain joined text (spaces between words).
    static func plain(_ words: [ProseWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    /// One `AttributedString` with isnād words in `isnad` and the Prophet's
    /// words (matn) in `matn`. A single space (isnād-coloured) joins words.
    static func attributed(_ words: [ProseWord], isnad: Color, matn: Color) -> AttributedString {
        var out = AttributedString()
        for (i, w) in words.enumerated() {
            if i > 0 {
                var sp = AttributedString(" ")
                sp.foregroundColor = isnad
                out += sp
            }
            var piece = AttributedString(w.text)
            piece.foregroundColor = (w.role == .matn) ? matn : isnad
            out += piece
        }
        return out
    }
}
