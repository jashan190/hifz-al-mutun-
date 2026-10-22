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

    /// Memorize mode: the live reveal (nil until the first word is judged).
    var reveal: RevealState? = nil

    /// True while Memorize mode is on — even before any word is revealed — so the
    /// body blanks out the instant you switch to it. (`reveal` alone can't tell
    /// Memorize-not-yet-started from Read mode, since both have a nil reveal.)
    var memorizing: Bool = false

    /// A word to briefly flash after jumping to a mistake (read mode only).
    var flashTarget: FlagKey? = nil

    /// Gap between wrapped lines; shared with the paginator's measurement.
    static func lineSpacing(for fontSize: CGFloat) -> CGFloat { fontSize * 0.5 }

    /// The `.sadr` half holds the hadith's whole body, so `revealedWords` is a
    /// prefix count over it: a word at body index `w` is shown iff `w < that`.
    private func shown(_ j: Int) -> Bool {
        guard memorizing else { return true }   // read mode: all shown
        guard let reveal else { return false }  // memorize, nothing revealed yet → blank
        return (fragment.bodyStart + j) < reveal.revealedWords(bayt: fragment.hadithNumber, half: .sadr)
    }
    private func wordColor(_ j: Int, _ role: ProseRole) -> UIColor {
        let base = role == .matn ? UIColor(subjectColor) : UIColor(Theme.ink)
        guard memorizing else { return base }               // read mode
        guard shown(j) else { return UIColor(Theme.cover) } // not yet reached → invisible ink
        guard let reveal else { return base }
        switch reveal.outcome(bayt: fragment.hadithNumber, half: .sadr, wordIndex: fragment.bodyStart + j) {
        case .wrong: return UIColor(Theme.error)            // said wrong (signal-red, not content-red)
        case .skipped, .unheard: return UIColor(Theme.ink.opacity(0.35))
        default: return base                                // correct / revealed / shown
        }
    }
    /// Unrevealed words draw their glyph in cream (invisible) but show a faint
    /// underline cue so the blank is visible; revealed words have no underline.
    private func wordUnderline(_ j: Int) -> UIColor? {
        (memorizing && !shown(j)) ? UIColor(Theme.ink.opacity(0.3)) : nil
    }

    private func wordBackground(_ j: Int) -> UIColor? {
        if memorizing {    // box the live mistakes
            guard let reveal else { return nil }
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
        guard !memorizing, let target = flashTarget,
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
                strokeColor: UIColor(Theme.errorEdge))
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
/// so this wraps a non-scrolling `UITextView`; its reported height uses the same
/// `boundingRect` the paginator measures with, so a page's text always fits.
/// The text view (not a bare label) is used so the mistake outline can be found
/// from the *same* layout manager that draws the glyphs — a separate TextKit
/// stack can position a justified RTL run a word off from what's on screen.
struct JustifiedText: UIViewRepresentable {
    let attributed: NSAttributedString
    /// The character range to outline (the tapped review word), or nil.
    var strokeRange: NSRange? = nil
    var strokeColor: UIColor = .red

    func makeUIView(context: Context) -> StrokeTextView {
        let tv = StrokeTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        return tv
    }

    func updateUIView(_ tv: StrokeTextView, context: Context) {
        tv.attributedText = attributed
        tv.strokeColor = strokeColor
        tv.strokeRange = strokeRange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StrokeTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let h = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return CGSize(width: width, height: ceil(h))
    }
}

/// A non-scrolling text view that outlines one character range (the tapped review
/// mistake). The rect comes from the view's own `layoutManager`, so it matches the
/// glyphs exactly — horizontally hugging the word via the selection-style
/// enclosing rects, vertically the line's used height (so it doesn't bleed into
/// the lines above and below).
final class StrokeTextView: UITextView {
    var strokeRange: NSRange? { didSet { setNeedsLayout() } }
    var strokeColor: UIColor = .red { didSet { strokeLayer.strokeColor = strokeColor.cgColor } }

    private let strokeLayer = CAShapeLayer()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = strokeColor.cgColor
        layer.addSublayer(strokeLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let length = textStorage.length
        guard let range = strokeRange, range.length > 0,
              range.location + range.length <= length else {
            strokeLayer.path = nil
            return
        }

        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { strokeLayer.path = nil; return }

        // Horizontal extent: the selection-style enclosing rects hug just this
        // word's glyphs. (boundingRect(forGlyphRange:) over-reports a justified RTL
        // run's width — it folds in the stretched word-spacing.)
        var hx: CGRect = .null
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs,
                                              withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                              in: textContainer) { r, _ in hx = hx.union(r) }
        guard !hx.isNull else { strokeLayer.path = nil; return }

        // Vertical extent: the USED height of the word's line fragment — the part
        // the glyphs actually occupy, matching the highlight fill (the full
        // line-fragment rect would also include the inter-line spacing).
        let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)

        // Container coordinates → view coordinates (inset is zero, but be explicit).
        var rect = CGRect(x: hx.minX + textContainerInset.left,
                          y: used.minY + textContainerInset.top,
                          width: hx.width, height: used.height)
        rect = rect.insetBy(dx: -2, dy: -1)
        strokeLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 5).cgPath
        strokeLayer.lineWidth = 2
    }
}
