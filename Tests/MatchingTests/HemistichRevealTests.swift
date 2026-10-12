import Testing
@testable import HifzAlMutun

@Suite struct HemistichRevealTests {
    // "في النظم أولا" is ONE segment spanning three words — the hard case.
    private func hemi() -> Hemistich {
        let words = ["في", "النظم", "أولا"]
        return Hemistich(
            text: words.joined(separator: " "),
            segments: [Segment(text: "في النظم أولا", color: .black, footnote: nil)],
            words: words.map { Word(text: $0, normalized: $0) }
        )
    }

    @Test func zeroWordsRevealsNothing() {
        #expect(HemistichReveal.prefix(hemi(), words: 0).isEmpty)
    }
    @Test func allWordsRevealsEverything() {
        let out = HemistichReveal.prefix(hemi(), words: 3)
        #expect(out.map { $0.text ?? "" }.joined() == "في النظم أولا")
    }
    @Test func splitsSpanningSegmentAtBoundary() {
        // Reveal first word only → "في"
        let out = HemistichReveal.prefix(hemi(), words: 1)
        #expect(out.map { $0.text ?? "" }.joined() == "في")
        #expect(out.first?.color == .black)
    }
    @Test func revealsAcrossTwoColouredSegments() {
        let words = ["بدأت", "بسم", "الله"]
        let h = Hemistich(
            text: "بدأت بسم الله",
            segments: [
                Segment(text: "بدأت ", color: .red, footnote: nil),
                Segment(text: "بسم الله", color: .black, footnote: nil),
            ],
            words: words.map { Word(text: $0, normalized: $0) }
        )
        let out = HemistichReveal.prefix(h, words: 2)   // "بدأت بسم"
        #expect(out.map { $0.text ?? "" }.joined() == "بدأت بسم")
        #expect(out.first?.color == .red)
        #expect(out.last?.color == .black)
    }

    // Real content carries harakat, so a word's scalar count (letters + marks)
    // exceeds its grapheme count. The cut must be scalar-based to land right.
    @Test func revealsWordWithHarakatByScalars() {
        let words = ["بِسْمِ", "اللهِ"]   // بِسْمِ = 6 scalars / 3 grapheme clusters
        let h = Hemistich(
            text: "بِسْمِ اللهِ",
            segments: [Segment(text: "بِسْمِ اللهِ", color: .black, footnote: nil)],
            words: words.map { Word(text: $0, normalized: $0) }
        )
        let out = HemistichReveal.prefix(h, words: 1)
        #expect(out.map { $0.text ?? "" }.joined() == "بِسْمِ")
    }

    // Footnote markers (text == nil) are kept only when they sit before the cut.
    private func hemiWithFootnote() -> Hemistich {
        let words = ["بدأت", "بسم"]
        return Hemistich(
            text: "بدأت بسم",
            segments: [
                Segment(text: "بدأت ", color: .black, footnote: nil),
                Segment(text: nil, color: nil, footnote: "٤"),   // marker after word 1
                Segment(text: "بسم", color: .black, footnote: nil),
            ],
            words: words.map { Word(text: $0, normalized: $0) }
        )
    }

    @Test func keepsFootnoteBeforeCut() {
        let out = HemistichReveal.prefix(hemiWithFootnote(), words: 2)
        #expect(out.contains { $0.footnote == "٤" })
    }

    @Test func dropsFootnoteAfterCut() {
        // Revealing only word 1 cuts inside "بدأت " — the marker that follows is dropped.
        let out = HemistichReveal.prefix(hemiWithFootnote(), words: 1)
        #expect(out.map { $0.text ?? "" }.joined() == "بدأت")
        #expect(!out.contains { $0.footnote == "٤" })
    }
}
