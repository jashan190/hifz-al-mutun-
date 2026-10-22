import SwiftUI
import UIKit

/// The fixed prose reading size; the paginator must measure with the same value.
let proseBodyFontSize: CGFloat = 24

/// Renders one `HadithFragment`: the heading (first page), the justified body
/// paragraph (Prophet's words in the subject colour), and the small takhrīj
/// (last page). The folio is drawn by the containing `PageView`. Assumes the
/// RTL layout the app root already provides.
struct ProsePageView: View {
    @EnvironmentObject private var flagStore: FlagStore

    let fragment: HadithFragment
    let subjectColor: Color
    let matnID: String
    /// Fixed, comfortable reading size for prose (not auto-fitted like poems).
    var fontSize: CGFloat = proseBodyFontSize

    /// Memorize mode: the live reveal (nil ⇒ plain read mode).
    var reveal: RevealState? = nil

    /// A word to briefly flash after jumping to a mistake (read mode only).
    var flashTarget: FlagKey? = nil

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
        case .wrong: return UIColor(Theme.error)            // said wrong (signal-red, not content-red)
        case .skipped, .unheard: return UIColor(Theme.ink.opacity(0.35))
        default: return base                                // correct / revealed / shown
        }
    }
    /// Unrevealed words draw their glyph in cream (invisible) but show a faint
    /// underline cue so the blank is visible; revealed words have no underline.
    private func wordUnderline(_ j: Int) -> UIColor? {
        (reveal != nil && !shown(j)) ? UIColor(Theme.ink.opacity(0.3)) : nil
    }

    private func wordBackground(_ j: Int) -> UIColor? {
        if let reveal {    // memorize: box the live mistakes
            switch reveal.outcome(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j) {
            case .wrong, .skipped: return UIColor(Theme.error).withAlphaComponent(0.12)
            default: return nil
            }
        }
        // read mode: box flagged words (the tapped one also gets a stroke outline).
        let key = FlagKey(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j)
        if flagStore.isFlagged(matnID, key) { return UIColor(Theme.error).withAlphaComponent(0.14) }
        return nil
    }

    /// The character range (in the justified body string) of the tapped review
    /// word, so `JustifiedText` can outline exactly its glyphs. Read mode only.
    private func strokeRange() -> NSRange? {
        guard reveal == nil, let target = flashTarget,
              target.bayt == fragment.hadithNumber, target.half == .sadr else { return nil }
        let j = target.wordIndex - fragment.bodyStart
        guard j >= 0, j < fragment.words.count else { return nil }
        var loc = 0
        for k in 0..<j { loc += (fragment.words[k].text as NSString).length + 1 } // +1 for the joining space
        return NSRange(location: loc, length: (fragment.words[j].text as NSString).length)
    }

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
                underline: { j in wordUnderline(j) },
                background: { j in wordBackground(j) }),
                strokeRange: strokeRange(),
                strokeColor: UIColor(Theme.error))
                .frame(maxWidth: .infinity)
                .contextMenu {
                    let flagged = fragment.words.indices.filter {
                        flagStore.isFlagged(matnID, FlagKey(bayt: fragment.hadithNumber,
                                                            half: .sadr, wordIndex: fragment.bodyStart + $0))
                    }
                    if flagged.isEmpty {
                        Text("No flagged words on this page")
                    } else {
                        ForEach(flagged, id: \.self) { j in
                            Button("Remove flag: \(fragment.words[j].text)", systemImage: "flag.slash") {
                                flagStore.setFlag(false, matnID: matnID,
                                    FlagKey(bayt: fragment.hadithNumber, half: .sadr,
                                            wordIndex: fragment.bodyStart + j))
                            }
                        }
                    }
                }
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
    /// The character range to outline (the tapped review word), or nil.
    var strokeRange: NSRange? = nil
    var strokeColor: UIColor = .red

    func makeUIView(context: Context) -> StrokeLabel {
        let label = StrokeLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        return label
    }

    func updateUIView(_ label: StrokeLabel, context: Context) {
        label.attributedText = attributed
        label.strokeColor = strokeColor
        label.strokeRange = strokeRange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StrokeLabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let h = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return CGSize(width: width, height: ceil(h))
    }
}

/// A UILabel that can draw a rounded-rect outline around one character range.
/// The rect is found with a TextKit stack matching the label's layout (same
/// string, same width, zero line-fragment padding), so it hugs the real glyphs
/// even across the justified RTL paragraph.
final class StrokeLabel: UILabel {
    var strokeRange: NSRange? { didSet { setNeedsLayout() } }
    var strokeColor: UIColor = .red { didSet { strokeLayer.strokeColor = strokeColor.cgColor } }

    private let strokeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = strokeColor.cgColor
        layer.addSublayer(strokeLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let attributedText, let range = strokeRange, bounds.width > 0 else {
            strokeLayer.path = nil
            return
        }

        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        // UILabel vertically centres its text when the view is taller than the text.
        let textHeight = manager.usedRect(for: container).height
        rect.origin.y += max(0, (bounds.height - textHeight) / 2)

        rect = rect.insetBy(dx: -3, dy: -2)
        strokeLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 5).cgPath
        strokeLayer.lineWidth = 1.5
    }
}
