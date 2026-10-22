import SwiftUI
import UIKit

/// Builds the hadith body text. One justified, line-spaced, role-coloured
/// attributed string is the SINGLE source used for both measurement (so the
/// paginator knows the exact laid-out height) and rendering (so a page never
/// needs to scroll — it turns when full).
enum ProseText {
    /// Plain joined text (spaces between words).
    static func plain(_ words: [ProseWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    /// The body as a justified RTL paragraph, each word styled by closures so the
    /// same builder serves read mode, memorize (reveal) mode, and measurement
    /// (colour/underline don't affect layout, so heights match across modes).
    /// `underline` returns the colour the word's underline should use, or nil for
    /// none. It's a colour (not a Bool) so an "invisible ink" word — glyph drawn
    /// in the page cream — can still show a visible underline cue (the underline
    /// defaults to the foreground colour otherwise, which would also be cream).
    static func attributed(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                           color: (_ index: Int, _ role: ProseRole) -> UIColor,
                           underline: (_ index: Int) -> UIColor?,
                           background: (_ index: Int) -> UIColor? = { _ in nil }) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineSpacing = lineSpacing
        para.baseWritingDirection = .rightToLeft
        let out = NSMutableAttributedString()
        for (i, w) in words.enumerated() {
            if i > 0 {
                out.append(NSAttributedString(string: " ",
                    attributes: [.font: font, .foregroundColor: color(i, w.role), .paragraphStyle: para]))
            }
            var attrs: [NSAttributedString.Key: Any] =
                [.font: font, .foregroundColor: color(i, w.role), .paragraphStyle: para]
            if let u = underline(i) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = u
            }
            if let bg = background(i) { attrs[.backgroundColor] = bg }
            out.append(NSAttributedString(string: w.text, attributes: attrs))
        }
        return out
    }

    /// The body as a justified RTL paragraph: isnād words in `isnad`, the
    /// Prophet's words (matn) in `matn`, joined by isnād-coloured spaces. The
    /// shared paragraph style (justified + lineSpacing) is what makes the lines
    /// fill the width evenly and makes measurement match layout.
    static func body(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                     isnad: UIColor, matn: UIColor) -> NSAttributedString {
        attributed(words, font: font, lineSpacing: lineSpacing,
                   color: { _, role in role == .matn ? matn : isnad },
                   underline: { _ in nil })
    }
}
