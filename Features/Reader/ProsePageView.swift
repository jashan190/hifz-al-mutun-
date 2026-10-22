import SwiftUI
import UIKit

/// The fixed prose reading size; the paginator must measure with the same value.
let proseBodyFontSize: CGFloat = 24

/// Renders one `HadithFragment`: the heading (first page), the justified body
/// paragraph (Prophet's words in the subject colour), and the small takhrīj
/// (last page). The folio is drawn by the containing `PageView`. Assumes the
/// RTL layout the app root already provides.
struct ProsePageView: View {
    let fragment: HadithFragment
    let subjectColor: Color
    /// Fixed, comfortable reading size for prose (not auto-fitted like poems).
    var fontSize: CGFloat = proseBodyFontSize

    /// Gap between wrapped lines; shared with the paginator's measurement.
    static func lineSpacing(for fontSize: CGFloat) -> CGFloat { fontSize * 0.5 }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if fragment.isFirst {
                Text(fragment.title)
                    .font(DisplayFont.title(size: fontSize * 0.9))
                    .foregroundStyle(subjectColor)
                    .multilineTextAlignment(.center)
            }
            JustifiedText(words: fragment.words,
                          font: PageFont.uiFont(size: fontSize),
                          lineSpacing: Self.lineSpacing(for: fontSize),
                          isnad: UIColor(Theme.ink),
                          matn: UIColor(subjectColor))
                .frame(maxWidth: .infinity)
            if fragment.isLast && !fragment.takhrij.isEmpty {
                // The attribution, kept small so it tucks under the text.
                Text(fragment.takhrij)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// A justified, multi-line Arabic paragraph. SwiftUI `Text` can't fully justify,
/// so this wraps a `UILabel`; its reported height uses the same `boundingRect`
/// the paginator measures with, so a page's text always fits (no scrolling).
struct JustifiedText: UIViewRepresentable {
    let words: [ProseWord]
    let font: UIFont
    let lineSpacing: CGFloat
    let isnad: UIColor
    let matn: UIColor

    private var attributed: NSAttributedString {
        ProseText.body(words, font: font, lineSpacing: lineSpacing, isnad: isnad, matn: matn)
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let h = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return CGSize(width: width, height: ceil(h))
    }
}
