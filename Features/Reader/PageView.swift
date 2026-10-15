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
    let page: Int
    let mode: PageMode
    var reveal: RevealState? = nil

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

    private let folioHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let items = matn.items(onPage: page)
            let bayts = matn.bayts(onPage: page)
            let columnWidth = max(
                1,
                (geo.size.width - 2 * hPadding - numberColumn - numberGap - midGap) / 2
            )
            let fontSize = pageFontSize(bayts: bayts, columnWidth: columnWidth)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            switch item {
                            case .heading(let heading):
                                HeadingRow(heading: heading, fontSize: fontSize)
                            case .bayt(let bayt):
                                BaytRow(
                                    bayt: bayt,
                                    mode: mode,
                                    fontSize: fontSize,
                                    columnWidth: columnWidth,
                                    justifyWidth: columnWidth * fitSafety,
                                    numberColumn: numberColumn,
                                    numberGap: numberGap,
                                    midGap: midGap,
                                    reveal: reveal
                                )
                            }
                            if index < items.count - 1 { Spacer(minLength: 8) }
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geo.size.height - folioHeight - 2 * Theme.margin,
                        alignment: .top
                    )
                    .padding(.horizontal, hPadding)
                    .padding(.top, Theme.margin)
                }
                folio
            }
        }
        .background(Theme.page)
    }

    // The folio: just the page number, centred at the foot of the page.
    private var folio: some View {
        Text(Numerals.eastern(page))
            .font(PageFont.font(size: 15))
            .foregroundStyle(Theme.numeral)
            .frame(maxWidth: .infinity)
            .frame(height: folioHeight)
            .accessibilityLabel("Page \(page)")
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
                                 outcome: outcome(k), fontSize: fontSize)
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
                    .accessibilityLabel("hidden")
            }
        }
        .frame(width: columnWidth, alignment: .leading)
        .frame(height: fontSize * 1.7, alignment: .center)
    }
}

// One recited word, styled by how it was judged:
//  - correct / not yet judged: the book's own colours
//  - unsure (a near miss): amber
//  - wrong: red on a soft red highlight, with what was heard in small type beneath
//  - skipped: red on a soft red highlight, struck through
// The highlight keeps a mistake distinct from words the book itself prints red.
//  - unheard (jumped while re-finding the place): secondary ink
private struct MemorizeWord: View {
    let segments: [Segment]
    let outcome: WordOutcome?
    let fontSize: CGFloat

    var body: some View {
        let plain = segments.compactMap(\.text).joined()
        LayeredText(
            rendered: HemistichText.render(
                segments: segments,
                plain: plain,
                size: fontSize,
                justifyWidth: 0,   // "no kashida", the sentinel headings use
                tint: tint
            ),
            font: PageFont.font(size: fontSize),
            size: fontSize
        )
        .fixedSize()
        .background {
            if outcome?.isMistake == true {
                RoundedRectangle(cornerRadius: fontSize * 0.18, style: .continuous)
                    .fill(Theme.error.opacity(0.10))   // keeps error text ≥4.5:1
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain)
        .accessibilityValue(accessibilityNote)
    }

    private func tint(_ color: SegmentColor) -> Color {
        switch outcome {
        case .none, .correct?: return inkColor(color)
        case .unsure?: return Theme.unsure
        case .wrong?, .skipped?: return Theme.error
        case .unheard?: return Theme.inkSecondary
        }
    }

    private var accessibilityNote: String {
        switch outcome {
        case .none, .correct?: return ""
        case .unsure?: return "unsure"
        case .wrong(let heard)?: return "mistake, heard \(heard)"
        case .skipped?: return "skipped"
        case .unheard?: return "not heard"
        }
    }
}

// A centred heading (bab/surah title, basmala, closing line). Rendered from its
// own segments, so the occasional blue/red part keeps its colour.
private struct HeadingRow: View {
    let heading: Heading
    let fontSize: CGFloat

    var body: some View {
        // Headings read in the Madinah green (the app's section colour); any blue
        // or red parts of a heading keep their own ink.
        let rendered = HemistichText.render(
            segments: heading.segments,
            plain: heading.text,
            size: fontSize * 1.2,
            justifyWidth: 0,                 // never kashida a heading
            tint: { $0 == .black ? Theme.accent : inkColor($0) }
        )
        LayeredText(rendered: rendered, font: PageFont.font(size: fontSize * 1.2),
                    size: fontSize * 1.2, defaultColor: Theme.accent)
            .padding(.vertical, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// A single bayt row: number + two equal-width, kashida-justified hemistichs.
private struct BaytRow: View {
    let bayt: Bayt
    let mode: PageMode
    let fontSize: CGFloat
    let columnWidth: CGFloat
    let justifyWidth: CGFloat
    let numberColumn: CGFloat
    let numberGap: CGFloat
    let midGap: CGFloat
    var reveal: RevealState? = nil

    private var lineHeight: CGFloat { fontSize * 1.7 }

    var body: some View {
        HStack(spacing: 0) {
            Text(Numerals.eastern(bayt.number))
                .font(PageFont.font(size: fontSize * 0.7))
                .foregroundStyle(Theme.numeral)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: numberColumn, alignment: .center)

            Color.clear.frame(width: numberGap)
            hemistich(bayt.sadr, which: .sadr)
            Color.clear.frame(width: midGap)
            hemistich(bayt.ajuz, which: .ajuz)
        }
        .accessibilityElement(children: .combine)   // VoiceOver: one element per bayt
        .frame(height: lineHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func hemistich(_ half: Hemistich, which: Half) -> some View {
        switch mode {
        case .read:
            LayeredText(
                rendered: HemistichText.render(
                    segments: half.segments,
                    plain: half.text,
                    size: fontSize,
                    justifyWidth: justifyWidth,
                    tint: inkColor
                ),
                font: PageFont.font(size: fontSize),
                size: fontSize,
                width: columnWidth
            )
        case .memorize:
            MemorizeHalf(
                half: half,
                revealed: reveal?.revealedWords(bayt: bayt.number, half: which) ?? 0,
                outcome: { reveal?.outcome(bayt: bayt.number, half: which, wordIndex: $0) },
                fontSize: fontSize,
                columnWidth: columnWidth
            )
        }
    }
}

#Preview("Read — light") {
    PageView(matn: .preview, page: 1, mode: .read)
}

#Preview("Memorize — light") {
    PageView(matn: .preview, page: 1, mode: .memorize)
}

#Preview("Read — dark") {
    PageView(matn: .preview, page: 1, mode: .read)
        .preferredColorScheme(.dark)
}

#Preview("Read — XL type") {
    PageView(matn: .preview, page: 1, mode: .read)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Memorize — revealing") {
    let matn = Matn.preview
    let idx = RecitationIndex(matn: matn)
    return PageView(matn: matn, page: 1, mode: .memorize,
                    reveal: RevealState(index: idx, cursor: 5))
}
