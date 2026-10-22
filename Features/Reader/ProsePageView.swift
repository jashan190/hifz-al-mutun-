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

    /// Memorize mode: the live reveal (nil ⇒ plain read mode).
    var reveal: RevealState? = nil

    /// Gap between wrapped lines; shared with the paginator's measurement.
    static func lineSpacing(for fontSize: CGFloat) -> CGFloat { fontSize * 0.5 }

    /// The `.sadr` half holds the hadith's whole body, so `revealedWords` is a
    /// prefix count over it: a word at body index `w` is shown iff `w < that`.
    private func shown(_ j: Int) -> Bool {
        guard let reveal else { return true }   // read mode: all shown
        return (fragment.bodyStart + j) < reveal.revealedWords(bayt: fragment.hadithNumber, half: .sadr)
    }
    private func wordColor(_ j: Int, _ role: ProseRole) -> UIColor {
        let base = role == .matn ? UIColor(subjectColor) : UIColor(Theme.ink)
        guard let reveal else { return base }               // read mode
        guard shown(j) else { return UIColor(Theme.cover) } // not yet reached → invisible ink
        switch reveal.outcome(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j) {
        case .wrong: return UIColor(Theme.rumuz)            // said wrong
        case .skipped, .unheard: return UIColor(Theme.ink.opacity(0.35))
        default: return base                                // correct / revealed / shown
        }
    }
    private func wordUnderline(_ j: Int) -> Bool { reveal != nil && !shown(j) }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if fragment.isFirst {
                Text(fragment.title)
                    .font(DisplayFont.title(size: fontSize * 0.9))
                    .foregroundStyle(subjectColor)
                    .multilineTextAlignment(.center)
            }
            JustifiedText(attributed: ProseText.attributed(
                fragment.words,
                font: PageFont.uiFont(size: fontSize),
                lineSpacing: Self.lineSpacing(for: fontSize),
                color: { j, role in wordColor(j, role) },
                underline: { j in wordUnderline(j) }))
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
    let attributed: NSAttributedString

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
