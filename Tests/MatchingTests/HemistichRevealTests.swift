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
        #expect(HemistichReveal.span(hemi(), words: 0..<0).isEmpty)
    }
    @Test func allWordsRevealsEverything() {
        let out = HemistichReveal.span(hemi(), words: 0..<3)
        #expect(out.map { $0.text ?? "" }.joined() == "في النظم أولا")
    }
    @Test func splitsSpanningSegmentAtBoundary() {
        // Reveal first word only → "في"
        let out = HemistichReveal.span(hemi(), words: 0..<1)
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
        let out = HemistichReveal.span(h, words: 0..<2)   // "بدأت بسم"
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
        let out = HemistichReveal.span(h, words: 0..<1)
        #expect(out.map { $0.text ?? "" }.joined() == "بِسْمِ")
    }

    // The book's "-" and "،" are tokens in `text` but not words; the cut must
    // step over them (bayt 74: «أَقُولُ لِحُرٍّ - وَالْمُرُوءَةُ مَرْؤُهَا»).
    @Test func skipsPunctuationTokens() {
        let words = ["أقول", "لحر", "والمروءة"]
        let h = Hemistich(
            text: "أقول لحر - والمروءة",
            segments: [Segment(text: "أقول لحر - والمروءة", color: .black, footnote: nil)],
            words: words.map { Word(text: $0, normalized: $0) }
        )
        let out = HemistichReveal.span(h, words: 0..<2)
        #expect(out.map { $0.text ?? "" }.joined() == "أقول لحر")
        let three = HemistichReveal.span(h, words: 0..<3)
        #expect(three.map { $0.text ?? "" }.joined() == "أقول لحر - والمروءة")
    }

    // Footnote markers (text == nil) sit right after the word they annotate, as
    // all 109 do in the Shatibiyyah data.
    private func hemiWithFootnote() -> Hemistich {
        let words = ["بدأت", "بسم"]
        return Hemistich(
            text: "بدأت بسم",
            segments: [
                Segment(text: "بدأت", color: .black, footnote: nil),
                Segment(text: nil, color: nil, footnote: "٤"),   // marker after word 1
                Segment(text: " بسم", color: .black, footnote: nil),
            ],
            words: words.map { Word(text: $0, normalized: $0) }
        )
    }

    @Test func keepsFootnoteBeforeCut() {
        let out = HemistichReveal.span(hemiWithFootnote(), words: 0..<2)
        #expect(out.contains { $0.footnote == "٤" })
    }

    @Test func dropsFootnoteOfAnUnrevealedWord() {
        let h = hemiWithFootnote()
        let marked = Hemistich(text: h.text, segments: [
            Segment(text: "بدأت ", color: .black, footnote: nil),
            Segment(text: "بسم", color: .black, footnote: nil),
            Segment(text: nil, color: nil, footnote: "٥"),       // marker after word 2
        ], words: h.words)
        let out = HemistichReveal.span(marked, words: 0..<1)
        #expect(out.map { $0.text ?? "" }.joined() == "بدأت")
        #expect(!out.contains { $0.footnote == "٥" })
    }

    // Memorize draws each word on its own: a single-word span is that word, and
    // a punctuation token goes with the word after it.
    @Test func singleWordSpans() {
        let words = ["أقول", "لحر", "والمروءة"]
        let h = Hemistich(
            text: "أقول لحر - والمروءة",
            segments: [Segment(text: "أقول ", color: .red, footnote: nil),
                       Segment(text: "لحر - والمروءة", color: .black, footnote: nil)],
            words: words.map { Word(text: $0, normalized: $0) }
        )
        let texts = (0..<3).map { HemistichReveal.span(h, words: $0..<($0 + 1)).compactMap(\.text).joined() }
        #expect(texts == ["أقول", "لحر", "- والمروءة"])
        #expect(HemistichReveal.span(h, words: 0..<1).first?.color == .red)
    }

    @Test func footnoteGoesWithTheWordItFollows() {
        let first = HemistichReveal.span(hemiWithFootnote(), words: 0..<1)
        let second = HemistichReveal.span(hemiWithFootnote(), words: 1..<2)
        #expect(first.contains { $0.footnote == "٤" })
        #expect(!second.contains { $0.footnote == "٤" })
        #expect(second.compactMap(\.text).joined() == "بسم")
    }
}

