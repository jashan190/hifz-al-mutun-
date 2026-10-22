import SwiftUI

enum PageMode: String, CaseIterable, Identifiable {
    case read       // display the text normally
    case memorize   // blank the hemistichs; show only bayt numbers (recall practice)
    var id: String { rawValue }
}

// One matn page. Mirrors the printed page: items (headings + bayts) are taken in
// print order from the content, each bayt a row of two hemistichs (sadr on the
// right, ajuz on the left) with its number on the right edge, and a centred
// heading wherever one sits between rows.
//
// Layout:
//  - one consistent font size for the whole page (fits the widest hemistich).
//  - the sadr and ajuz each live in an equal, fixed-width container a set gap
//    apart; each hemistich is justified with kashida to fill its container.
//  - rows are distributed down the full height so the page fills the screen;
//    large Dynamic Type makes it taller and it scrolls.
struct PageView: View {
    let matn: Matn
    let pageModel: MatnPage
    let mode: PageMode
    var reveal: RevealState? = nil
    var flashTarget: FlagKey? = nil

    // Tighter margins/gaps give each hemistich more width, which — since the text
    // is sized to fill its column — makes the glyphs noticeably larger.
    private let hPadding: CGFloat = 10
    private let numberColumn: CGFloat = 30
    private let numberGap: CGFloat = 6
    private let midGap: CGFloat = 14
    private let referenceSize: CGFloat = 40
    private let minSize: CGFloat = 12
    private let maxSize: CGFloat = 48
    // Width measurement underestimates SwiftUI's rendered width, so size and
    // justify to a slightly conservative target to avoid truncation.
    private let fitSafety: CGFloat = 0.99

    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    static let folioHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let items = pageModel.items
            let bayts = items.compactMap { if case .bayt(let b) = $0 { return b } else { return nil } }
            let columnWidth = max(
                1,
                (geo.size.width - 2 * hPadding - numberColumn - numberGap - midGap) / 2
            )
            let fontSize = pageFontSize(bayts: bayts, columnWidth: columnWidth)
            // A full page (its quota of bayts) distributes its rows to fill the
            // page height; an under-filled last page keeps its gaps capped so it
            // sits at the top instead of ballooning.
            let fillPage = bayts.count >= matn.baytsPerPage

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            switch item {
                            case .heading(let heading):
                                HeadingRow(heading: heading, fontSize: fontSize,
                                           tint: matn.subject.accent)
                            case .bayt(let bayt):
                                BaytRow(
                                    matnID: matn.id,
                                    bayt: bayt,
                                    mode: mode,
                                    fontSize: fontSize,
                                    columnWidth: columnWidth,
                                    justifyWidth: columnWidth * fitSafety,
                                    numberColumn: numberColumn,
                                    numberGap: numberGap,
                                    midGap: midGap,
                                    subjectColor: matn.subject.accent,
                                    reveal: reveal,
                                    flashTarget: flashTarget
                                )
                            case .hadith(let fragment):
                                ProsePageView(fragment: fragment,
                                              subjectColor: matn.subject.accent,
                                              matnID: matn.id,
                                              reveal: mode == .memorize ? reveal : nil,
                                              flashTarget: flashTarget)
                            }
                            // Spacers distribute items down the page. On a full
                            // page they expand so the rows fill the height; on an
                            // under-filled last page they're capped so it sits at
                            // the top instead of ballooning the gaps.
                            if index < items.count - 1 {
                                if fillPage {
                                    Spacer(minLength: 8)
                                } else {
                                    Spacer(minLength: 8).frame(maxHeight: 22)
                                }
                            }
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geo.size.height - Self.folioHeight - 2 * Theme.margin,
                        alignment: .top
                    )
                    .padding(.horizontal, hPadding)
                    .padding(.top, Theme.margin)
                }
                folio
            }
        }
        .background(Theme.cover)
    }

    // The folio: just the page number, centred at the foot of the page.
    private var folio: some View {
        Text(Numerals.eastern(pageModel.page))
            .font(PageFont.font(size: 15))
            .foregroundStyle(Theme.numeral)
            .frame(maxWidth: .infinity)
            .frame(height: Self.folioHeight)
            .accessibilityLabel("Page \(pageModel.page)")
    }

    private func pageFontSize(bayts: [Bayt], columnWidth: CGFloat) -> CGFloat {
        let target = columnWidth * fitSafety
        var best = maxSize
        for bayt in bayts {
            for text in [bayt.sadr.text, bayt.ajuz.text] {
                let w = PageFont.width(text, size: referenceSize)
                guard w > 0 else { continue }
                best = min(best, referenceSize * target / w)
            }
        }
        return min(max(best, minSize), maxSize) * typeScale
    }
}

/// Map a segment colour to the theme ink/quran/rumuz tokens.
func inkColor(_ color: SegmentColor) -> Color {
    switch color {
    case .black: return Theme.ink
    case .blue:  return Theme.quran
    case .red:   return Theme.rumuz
    }
}

// Stacks a half-line's base text with its shifted small-nun layers. The nun
// layers are moved with `.offset` (no effect on layout), so a nun can sit well
// above or below the word without knocking the row out of alignment.
private struct LayeredText: View {
    let rendered: HemistichText.Rendered
    let font: Font
    let size: CGFloat
    var width: CGFloat? = nil          // fixed column (hemistich) or nil (heading)
    var defaultColor: Color = Theme.ink

    var body: some View {
        ZStack(alignment: width == nil ? .center : .leading) {
            layer(rendered.base)
            // The shifted nuns are also nudged slightly left (positive x reads as
            // leftward under RTL) so they sit in the gap between words, clear of the
            // neighbouring letters' tashkīl.
            if let above = rendered.above {
                layer(above).offset(x: size * HemistichText.noonShift, y: -size * HemistichText.noonRise)
            }
            if let below = rendered.below {
                layer(below).offset(x: size * HemistichText.noonShift, y: size * HemistichText.noonFall)
            }
            if let kasra = rendered.belowKasra {
                layer(kasra).offset(x: size * HemistichText.noonShift,
                                    y: size * (HemistichText.noonFall - HemistichText.noonKasraLift))
            }
            // Footnote markers float above the line at their x, so they never steal
            // width from the bayt. `lead` is the distance from the leading (right,
            // in RTL) edge; move left by that to sit just after the footnoted word.
            ForEach(Array(rendered.footnotes.enumerated()), id: \.offset) { _, fn in
                Text(fn.marker)
                    .font(PageFont.font(size: size * 0.5))
                    .foregroundStyle(Theme.numeral)
                    .fixedSize()
                    .offset(x: fn.lead, y: -size * HemistichText.footnoteLift)
            }
            // A darker outline around the tapped review word (positive x reads as
            // leftward under RTL), so you can spot it among the flagged red boxes.
            if let fb = rendered.flashBox, width != nil {
                let pad = size * 0.14
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(Theme.error, lineWidth: max(1.5, size * 0.045))
                    .frame(width: fb.width + pad * 2, height: size * 1.2)
                    .offset(x: fb.lead - pad, y: 0)
            }
        }
    }

    @ViewBuilder
    private func layer(_ s: AttributedString) -> some View {
        let text = Text(s).font(font).foregroundStyle(defaultColor)
        if let width {
            text.lineLimit(1).minimumScaleFactor(0.9)
                .frame(width: width, alignment: .leading)
        } else {
            text.multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
}

// A half-line in Memorize mode: the first `revealed` words, each drawn as its
// own view in its real colours (or its mistake colour), filling from the right
// (RTL); the rest stays a single faint blank line, so word lengths never show.
private struct MemorizeHalf: View {
    let half: Hemistich
    let revealed: Int
    var outcome: (Int) -> WordOutcome? = { _ in nil }
    var heard: (Int) -> String? = { _ in nil }
    var added: (Int) -> String? = { _ in nil }
    var flagged: (Int) -> Bool = { _ in false }
    var onDismiss: (Int) -> Void = { _ in }
    var onDismissAdded: (Int) -> Void = { _ in }
    var onToggleFlag: (Int) -> Void = { _ in }
    var onTapBlank: (() -> Void)? = nil
    let fontSize: CGFloat
    let columnWidth: CGFloat

    var body: some View {
        // The app lays out right-to-left, so the HStack's first child sits on the
        // right: revealed words start at the column's leading (right) edge, next
        // to the bayt number, and the blank remainder takes the rest on the left.
        HStack(spacing: 0) {
            HStack(spacing: PageFont.width(" ", size: fontSize)) {
                ForEach(0..<revealed, id: \.self) { k in
                    MemorizeWord(segments: HemistichReveal.span(half, words: k..<(k + 1)),
                                 outcome: outcome(k), heard: heard(k), flagged: flagged(k), fontSize: fontSize,
                                 onDismiss: { onDismiss(k) }, onToggleFlag: { onToggleFlag(k) })
                    if let words = added(k) {
                        AddedMark(words: words, fontSize: fontSize) { onDismissAdded(k) }
                    }
                }
            }
            .fixedSize()
            // Blank remainder. It flexes to fill whatever space the natural-width
            // revealed words leave, so we never measure text width ourselves
            // (which can disagree with SwiftUI's layout and overflow).
            if revealed < half.words.count {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.outline)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, revealed > 0 ? 6 : 0)
                    // Stuck? Tap the blank to reveal the next word. The tap area is
                    // the whole row height, not just the thin line.
                    .frame(height: fontSize * 1.7)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapBlank?() }
                    .allowsHitTesting(onTapBlank != nil)
                    .accessibilityLabel("hidden")
            }
        }
        .frame(width: columnWidth, alignment: .leading)
        .frame(height: fontSize * 1.7, alignment: .center)
    }
}

// One recited word, styled by how it was judged:
//  - correct / not yet judged: the book's own colours
//  - unsure (a near miss): on a soft amber highlight, the letters that differ
//    from what was heard amber
//  - wrong: on a soft red highlight, the letters that differ (with their
//    harakat) red, and what was heard in small type beneath
//  - skipped: red on a soft red highlight, struck through
// The highlight keeps a mistake distinct from words the book itself prints red.
//  - unheard (jumped while re-finding the place): secondary ink
//  - revealed (shown as help when stuck): secondary ink, and flagged
// A flagged word carries the flag underline in every state.
private struct MemorizeWord: View {
    let segments: [Segment]
    let outcome: WordOutcome?
    /// What was heard, for an amber or red word: only its differing letters
    /// are coloured. Without it the whole word is.
    var heard: String? = nil
    var flagged = false
    let fontSize: CGFloat
    var onDismiss: () -> Void = {}
    var onToggleFlag: () -> Void = {}

    var body: some View {
        let plain = segments.compactMap(\.text).joined()
        LayeredText(
            rendered: HemistichText.render(
                segments: segments,
                plain: plain,
                size: fontSize,
                justifyWidth: 0,   // "no kashida", the sentinel headings use
                // The rest of the word in plain ink, so the marked letters
                // stand out even in a word the book prints red or blue.
                tint: letters(plain) == nil ? tint : { _ in Theme.ink },
                underlined: flagged ? [0..<plain.unicodeScalars.count] : [],
                emphasis: letters(plain).map { ($0, tint(.black)) }
            ),
            font: PageFont.font(size: fontSize),
            size: fontSize
        )
        .fixedSize()
        .background {
            if outcome?.isMistake == true || outcome == .unsure {
                RoundedRectangle(cornerRadius: fontSize * 0.18, style: .continuous)
                    .fill(outcome == .unsure ? Theme.unsure.opacity(0.12)
                          : Theme.error.opacity(0.10))   // keeps error text ≥4.5:1
                    .padding(.horizontal, -fontSize * 0.1)
                    .padding(.vertical, fontSize * 0.12)
            }
        }
        .overlay {
            if outcome == .skipped {
                Rectangle().fill(Theme.error)
                    .frame(height: max(1, fontSize * 0.05))
                    .offset(y: fontSize * HemistichText.strikeDrop)
            }
        }
        .overlay(alignment: .bottom) {
            if case .wrong(let heard) = outcome {
                // Floats under the word without taking layout space.
                Text(heard)
                    .font(PageFont.font(size: fontSize * 0.42))
                    .foregroundStyle(Theme.error)
                    .fixedSize()
                    .offset(y: fontSize * HemistichText.heardDrop)
            }
        }
        // Voice recognition can be wrong: long-press a red word to clear it.
        .contextMenu {
            if outcome?.isMistake == true {
                Button("Not a mistake", systemImage: "checkmark.circle", action: onDismiss)
            } else {
                Button(flagged ? "Remove flag" : "Flag mistake",
                       systemImage: flagged ? "flag.slash" : "flag", action: onToggleFlag)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain)
        .accessibilityValue(accessibilityNote)
    }

    /// The letters to colour as the mistake, when what was heard is known
    /// and shares some letters with the word (else the whole word is coloured).
    private func letters(_ plain: String) -> [Range<Int>]? {
        guard let heard else { return nil }
        switch outcome {
        case .unsure?, .wrong?: break
        default: return nil
        }
        let ranges = LetterEmphasis.ranges(written: plain, heard: heard)
        let total = ArabicNormalize.letterRanges(plain).count
        return ranges.isEmpty || ranges.count >= total ? nil : ranges
    }

    private func tint(_ color: SegmentColor) -> Color {
        switch outcome {
        case .none, .correct?, .shown?: return inkColor(color)
        case .unsure?: return Theme.unsure
        case .wrong?, .skipped?: return Theme.error
        case .unheard?, .revealed?: return Theme.inkSecondary
        }
    }

    private var accessibilityNote: String {
        switch outcome {
        case .none, .correct?, .shown?: return ""
        case .unsure?: return "unsure"
        case .wrong(let heard)?: return "mistake, heard \(heard)"
        case .skipped?: return "skipped"
        case .unheard?: return "not heard"
        case .revealed?: return "revealed"
        }
    }
}

// Words said that the text doesn't have, after the word they followed: a red
// plus in the gap, with the words in small type beneath (as a wrong word's
// heard text). Long-press to clear it.
private struct AddedMark: View {
    let words: String
    let fontSize: CGFloat
    var onDismiss: () -> Void = {}

    var body: some View {
        // As wide as the words beneath, so they don't run under the next word.
        Text(words)
            .font(PageFont.font(size: fontSize * 0.42))
            .fixedSize()
            .hidden()
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.42, weight: .bold))
                    .foregroundStyle(Theme.error)
                    .padding(fontSize * 0.1)
                    .background(Circle().fill(Theme.error.opacity(0.10)))
                    .fixedSize()
            }
            .overlay(alignment: .bottom) {
                Text(words)
                    .font(PageFont.font(size: fontSize * 0.42))
                    .foregroundStyle(Theme.error)
                    .fixedSize()
                    .offset(y: fontSize * HemistichText.heardDrop)
            }
            .contextMenu {
                Button("Not a mistake", systemImage: "checkmark.circle", action: onDismiss)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("mistake, added \(words)")
    }
}

// A centred heading (bab/surah title, basmala, closing line). Rendered from its
// own segments, so the occasional blue/red part keeps its colour.
private struct HeadingRow: View {
    let heading: Heading
    let fontSize: CGFloat
    var tint: Color = Theme.accent   // the matn's subject colour for headings

    var body: some View {
        // Headings read in the Madinah green (the app's section colour); any blue
        // or red parts of a heading keep their own ink.
        let rendered = HemistichText.render(
            segments: heading.segments,
            plain: heading.text,
            size: fontSize * 1.2,
            justifyWidth: 0,                 // never kashida a heading
            tint: { $0 == .black ? tint : inkColor($0) }
        )
        LayeredText(rendered: rendered, font: PageFont.font(size: fontSize * 1.2),
                    size: fontSize * 1.2, defaultColor: tint)
            .padding(.vertical, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// A single bayt row: number + two equal-width, kashida-justified hemistichs.
private struct BaytRow: View {
    @EnvironmentObject private var flagStore: FlagStore
    @Environment(\.readerActions) private var actions

    let matnID: String
    let bayt: Bayt
    let mode: PageMode
    let fontSize: CGFloat
    let columnWidth: CGFloat
    let justifyWidth: CGFloat
    let numberColumn: CGFloat
    let numberGap: CGFloat
    let midGap: CGFloat
    var subjectColor: Color = Theme.accent   // the matn's subject colour
    var reveal: RevealState? = nil
    var flashTarget: FlagKey? = nil

    private var lineHeight: CGFloat { fontSize * 1.7 }

    var body: some View {
        HStack(spacing: 0) {
            number
            Color.clear.frame(width: numberGap)
            hemistich(bayt.sadr, which: .sadr)
            Color.clear.frame(width: midGap)
            hemistich(bayt.ajuz, which: .ajuz)
        }
        .accessibilityElement(children: .combine)   // VoiceOver: one element per bayt
        .accessibilityActions {
            if mode == .memorize {
                Button("Recite from this bayt") { actions.startFromBayt(bayt.number) }
                Button("Reveal the next word") { actions.revealNext(bayt.number) }
            }
        }
        .frame(height: lineHeight)
        .frame(maxWidth: .infinity)
    }

    // In Memorize, tapping the number starts reciting from this bayt.
    @ViewBuilder
    private var number: some View {
        let label = Text(Numerals.eastern(bayt.number))
            .font(PageFont.font(size: fontSize * 0.7))
            .foregroundStyle(mode == .memorize ? subjectColor : Theme.numeral)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: numberColumn, height: lineHeight, alignment: .center)
            .contentShape(Rectangle())
        if mode == .memorize {
            label.onTapGesture { actions.startFromBayt(bayt.number) }
        } else {
            label
        }
    }

    private func flagged(_ which: Half, _ k: Int) -> Bool {
        flagStore.isFlagged(matnID, FlagKey(bayt: bayt.number, half: which, wordIndex: k))
    }

    @ViewBuilder
    private func hemistich(_ half: Hemistich, which: Half) -> some View {
        switch mode {
        case .read:
            let ranges = HemistichReveal.wordRanges(in: half.text)
            let flagRanges = ranges.indices.filter { flagged(which, $0) }.map { ranges[$0] }
            let flashRanges: [Range<Int>] = {
                guard let f = flashTarget, f.bayt == bayt.number, f.half == which,
                      f.wordIndex < ranges.count else { return [] }
                return [ranges[f.wordIndex]]
            }()
            LayeredText(
                rendered: HemistichText.render(
                    segments: half.segments,
                    plain: half.text,
                    size: fontSize,
                    justifyWidth: justifyWidth,
                    tint: inkColor,
                    boxed: flagRanges,
                    flashBoxed: flashRanges
                ),
                font: PageFont.font(size: fontSize),
                size: fontSize,
                width: columnWidth
            )
            // Long-press: flag or unflag any word of this half-line. The page is
            // justified as one line, so the menu lists its words.
            .contentShape(Rectangle())
            .contextMenu {
                ForEach(Array(half.words.enumerated()), id: \.offset) { k, word in
                    let on = flagged(which, k)
                    Button(on ? "Remove flag: \(word.text)" : "Flag mistake: \(word.text)",
                           systemImage: on ? "flag.slash" : "flag") {
                        flagStore.setFlag(!on, matnID: matnID,
                                          FlagKey(bayt: bayt.number, half: which, wordIndex: k))
                    }
                }
            }
        case .memorize:
            MemorizeHalf(
                half: half,
                revealed: reveal?.revealedWords(bayt: bayt.number, half: which) ?? 0,
                outcome: { reveal?.outcome(bayt: bayt.number, half: which, wordIndex: $0) },
                heard: { reveal?.heard(bayt: bayt.number, half: which, wordIndex: $0) },
                added: { reveal?.added(bayt: bayt.number, half: which, wordIndex: $0) },
                flagged: { flagged(which, $0) },
                onDismiss: { actions.dismissMistake(bayt.number, which, $0) },
                onDismissAdded: { actions.dismissAdded(bayt.number, which, $0) },
                onToggleFlag: { k in
                    flagStore.setFlag(!flagged(which, k), matnID: matnID,
                                      FlagKey(bayt: bayt.number, half: which, wordIndex: k))
                },
                // Only the blank holding the next word reveals it; elsewhere a
                // tap falls through to show/hide the bars.
                onTapBlank: reveal?.holdsCursor(bayt: bayt.number, half: which) == true
                    ? { actions.revealNext(bayt.number) } : nil,
                fontSize: fontSize,
                columnWidth: columnWidth
            )
        }
    }
}

private let previewPage = Matn.preview.pages.first ?? MatnPage(page: 1, items: [])

#Preview("Read — light") {
    PageView(matn: .preview, pageModel: previewPage, mode: .read)
        .environmentObject(FlagStore.inMemory())
}

#Preview("Memorize — light") {
    PageView(matn: .preview, pageModel: previewPage, mode: .memorize)
        .environmentObject(FlagStore.inMemory())
}

#Preview("Read — dark") {
    PageView(matn: .preview, pageModel: previewPage, mode: .read)
        .environmentObject(FlagStore.inMemory())
        .preferredColorScheme(.dark)
}

#Preview("Read — XL type") {
    PageView(matn: .preview, pageModel: previewPage, mode: .read)
        .environmentObject(FlagStore.inMemory())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Memorize — revealing") {
    let matn = Matn.preview
    let idx = RecitationIndex(matn: matn)
    return PageView(matn: matn, pageModel: matn.pages.first ?? MatnPage(page: 1, items: []), mode: .memorize,
                    reveal: RevealState(index: idx, cursor: 5, outcomes: [2: .unsure, 3: .wrong(heard: "كلمة"), 4: .skipped]))
        .environmentObject(FlagStore.inMemory())
}
