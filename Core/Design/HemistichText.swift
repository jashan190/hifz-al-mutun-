import SwiftUI

// Builds the coloured, justified text for one half-line.
//
// A half-line is drawn as AttributedStrings so Arabic letters keep joining even
// when a colour run is a single letter inside a word (the farsh رموز). Colour
// comes from the `segments`; footnote markers render as small raised numbers.
//
// The small nun (U+06E8) is special: depending on the vowel it carries while
// joining it must sit clearly ABOVE or BELOW the word. A big vertical shift via
// baselineOffset would distort the line's metrics and knock the row out of
// alignment, so instead we render the nun on its own transparent *layer* that is
// moved with `.offset` (which doesn't affect layout). `render` returns the base
// text plus optional above/below layers; the view stacks them.
//
// Justification is by kashida (tatweel, U+0640): we lengthen baseline joins
// inside words so the half-line fills its column the way the printed page does.
// We work on Unicode *scalars* (a Character would hide a base letter inside its
// grapheme cluster) and never add a kashida after a non-joining letter or inside
// a lām-alif ligature.

enum HemistichText {
    private static let tatweel = Unicode.Scalar(0x0640)!

    // Letters that do NOT join to the following letter — no kashida after these.
    //  ا أ إ آ ء ؤ د ذ ر ز و ة ى
    private static let noJoinLeft: Set<UInt32> = [
        0x0627, 0x0623, 0x0625, 0x0622, 0x0621, 0x0624,
        0x062F, 0x0630, 0x0631, 0x0632, 0x0648, 0x0629, 0x0649,
    ]
    private static let alefForms: Set<UInt32> = [0x0627, 0x0623, 0x0625, 0x0622]

    private static func isLetter(_ s: Unicode.Scalar) -> Bool {
        (0x0621...0x064A).contains(s.value)
    }
    // All combining marks we may meet, including the Uthmani set (dagger alif,
    // round sukun, small waw/ya/nun, maddah, dot below…) so they don't hide the
    // next base letter from the joining test.
    private static func isMark(_ s: Unicode.Scalar) -> Bool {
        (0x064B...0x065F).contains(s.value) || s.value == 0x0670 || (0x06D6...0x06ED).contains(s.value)
    }
    private static func joinsLeft(_ s: Unicode.Scalar) -> Bool {
        isLetter(s) && !noJoinLeft.contains(s.value)
    }
    private static func isLamAlef(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> Bool {
        a.value == 0x0644 && alefForms.contains(b.value)
    }

    /// Eligible kashida insertion offsets in `scalars`: an offset `o` means insert
    /// tatweel *before* scalar `o`, i.e. right after a joining base letter and its
    /// marks, when the next scalar is a letter and not a lām-alif pair.
    private static func insertionOffsets(_ scalars: [Unicode.Scalar]) -> [Int] {
        var points: [Int] = []
        var i = 0
        while i < scalars.count {
            var j = i + 1
            while j < scalars.count && isMark(scalars[j]) { j += 1 }
            if joinsLeft(scalars[i]), j < scalars.count, isLetter(scalars[j]), !isLamAlef(scalars[i], scalars[j]) {
                points.append(j)
            }
            i = j
        }
        return points
    }

    /// Tatweel counts to add, keyed by the global scalar offset they go *before*,
    /// spread evenly so the half-line fills `targetWidth`. Empty if it already
    /// fills or there's nowhere valid to add kashida.
    private static func kashida(plain: String, targetWidth: CGFloat, size: CGFloat) -> [Int: Int] {
        let unit = PageFont.width("\u{0640}", size: size)
        let deficit = targetWidth - PageFont.width(plain, size: size)
        guard unit > 0, deficit > unit else { return [:] }

        let scalars = Array(plain.unicodeScalars)
        let points = insertionOffsets(scalars)
        guard !points.isEmpty else { return [:] }

        var remaining = max(0, Int((deficit / unit).rounded()))
        var result: [Int: Int] = [:]
        var k = 0
        let safety = points.count * 16
        while remaining > 0 && k < safety {
            result[points[k % points.count], default: 0] += 1
            remaining -= 1
            k += 1
        }
        return result
    }

    // MARK: - Small-nun placement

    private static let smallNoon: UInt32 = 0x06E8
    private static let fatha: UInt32 = 0x064E
    private static let damma: UInt32 = 0x064F
    private static let kasra: UInt32 = 0x0650
    private static let sukun: UInt32 = 0x0652

    /// The four harakāt a small nun may carry in the source.
    private static func isNoonHaraka(_ v: UInt32) -> Bool {
        v == fatha || v == damma || v == kasra || v == sukun
    }

    enum NoonPlace { case above, below, natural }

    /// Where each U+06E8 in `plain` should sit, keyed by its 0-based scalar index.
    /// We follow the printed book: the vowel drawn on a *connecting* nun (word-final,
    /// joining the next word) tells us where it rides — a **kasra** hangs it BELOW
    /// the line, a **fatḥa/ḍamma** lifts it ABOVE. A nun still followed by a letter
    /// (after its vowel) is a mid-word spelling nun and stays put. A bare connecting
    /// nun with no vowel defaults BELOW, as the book draws most of them.
    private static func noonPlacements(_ plain: String) -> [Int: NoonPlace] {
        let sc = Array(plain.unicodeScalars)
        var map: [Int: NoonPlace] = [:]
        for i in sc.indices where sc[i].value == smallNoon {
            var j = i + 1
            var vowel: UInt32?
            if j < sc.count, isNoonHaraka(sc[j].value) { vowel = sc[j].value; j += 1 }
            if j == sc.count || sc[j].value == 0x20 {           // connecting nun
                map[i] = (vowel == fatha || vowel == damma) ? .above : .below
            } else {
                map[i] = .natural                               // mid-word spelling nun
            }
        }
        return map
    }

    // MARK: - Rendering

    /// The layers of a half-line. `above`/`below` hold only the shifted nuns and
    /// `footnotes` hold the raised markers — everything else on them is
    /// transparent, so they can be `.offset` without touching the base layout
    /// (the base is exactly the half-line's text, so it fills its column without
    /// footnotes stealing width). nil/empty when there's nothing to shift.
    struct Rendered {
        var base: AttributedString
        var above: AttributedString?
        var below: AttributedString?
        var footnotes: [Footnote]
    }

    /// A footnote marker to float above the line. `lead` is its distance from the
    /// start (leading/right) edge of the half-line, so the view can place it at
    /// the right spot without it stealing any width from the base text.
    struct Footnote {
        var marker: String    // already wrapped, e.g. "(٦)"
        var lead: CGFloat
    }

    private enum Slot { case normal, above, below }

    /// Build the base text plus optional above/below nun layers and footnote
    /// layers for a half-line. `plain` is the half-line's `text`.
    static func render(
        segments: [Segment],
        plain: String,
        size: CGFloat,
        justifyWidth: CGFloat,
        tint: (SegmentColor) -> Color
    ) -> Rendered {
        let insertions = kashida(plain: plain, targetWidth: justifyWidth, size: size)
        let placements = noonPlacements(plain)

        var base = AttributedString()
        var above = AttributedString()
        var below = AttributedString()
        var prefixPlain = ""        // display text so far (with tatweel), for width
        var footnotes: [Footnote] = []
        var hasAbove = false, hasBelow = false

        // Append the same glyph to every layer, visible only on the slot that owns
        // it, so all layers share identical metrics → identical x positions.
        func add(_ text: String, color: Color, slot: Slot) {
            func piece(_ c: Color) -> AttributedString {
                var a = AttributedString(text)
                a.foregroundColor = c
                return a
            }
            base += piece(slot == .normal ? color : .clear)
            above += piece(slot == .above ? color : .clear)
            below += piece(slot == .below ? color : .clear)
            prefixPlain += text
        }

        var global = 0   // 0-based scalar cursor over `plain`

        for seg in segments {
            if let marker = seg.footnote {
                // Record a floating marker at its x (distance into the line) so the
                // view can place it above the line without it taking any width.
                footnotes.append(Footnote(marker: "(\(marker))",
                                          lead: PageFont.width(prefixPlain, size: size)))
                continue
            }
            guard let runText = seg.text else { continue }
            let color = tint(seg.color ?? .black)
            let run = Array(runText.unicodeScalars)
            var i = 0
            while i < run.count {
                let s = run[i]
                let pidx = global
                global += 1
                var piece = String(s)
                if let place = placements[pidx], s.value == smallNoon, place != .natural {
                    // Pull the nun's vowel (kasra below, fatḥa/ḍamma above) into the
                    // same shifted piece so the mark travels with the nun.
                    if i + 1 < run.count, isNoonHaraka(run[i + 1].value) {
                        piece += String(run[i + 1]); i += 1; global += 1
                    }
                    if let n = insertions[global] { piece += String(repeating: "\u{0640}", count: n) }
                    if place == .above { hasAbove = true } else { hasBelow = true }
                    add(piece, color: color, slot: place == .above ? .above : .below)
                } else {
                    if let n = insertions[global] { piece += String(repeating: "\u{0640}", count: n) }
                    add(piece, color: color, slot: .normal)
                }
                i += 1
            }
        }

        return Rendered(
            base: base,
            above: hasAbove ? above : nil,
            below: hasBelow ? below : nil,
            footnotes: footnotes
        )
    }

    // Offsets (× size) for the shifted layers.
    static let noonRise: CGFloat = 0.45    // fatḥa/ḍamma nun, just above the word
    static let noonFall: CGFloat = 1.45    // kasra nun, clearly below the word
    static let noonShift: CGFloat = 0.32   // nudge left (into the gap between words)
    static let footnoteLift: CGFloat = 1.15 // footnote marker, above the line
}
