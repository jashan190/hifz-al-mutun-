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

    /// The body as a justified RTL paragraph: isnād words in `isnad`, the
    /// Prophet's words (matn) in `matn`, joined by isnād-coloured spaces. The
    /// shared paragraph style (justified + lineSpacing) is what makes the lines
    /// fill the width evenly and makes measurement match layout.
    static func body(_ words: [ProseWord], font: UIFont, lineSpacing: CGFloat,
                     isnad: UIColor, matn: UIColor) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineSpacing = lineSpacing
        para.baseWritingDirection = .rightToLeft
        let out = NSMutableAttributedString()
        for (i, w) in words.enumerated() {
            if i > 0 {
                out.append(NSAttributedString(string: " ",
                    attributes: [.font: font, .foregroundColor: isnad, .paragraphStyle: para]))
            }
            let color = (w.role == .matn) ? matn : isnad
            out.append(NSAttributedString(string: w.text,
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para]))
        }
        return out
    }
}
