import Testing
@testable import HifzAlMutun

@Suite struct RevealStateTests {
    private func index() -> RecitationIndex {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: $0) })
        }
        let b = Bayt(number: 1, sadr: hemi(["a", "b"]), ajuz: hemi(["c", "d"]))
        let page = MatnPage(page: 1, items: [.bayt(b)])
        return RecitationIndex(matn: Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t",
            author: "a", meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
            pages: [page], babs: [], reviewNotes: []))
    }

    @Test func mapsCursorToPerHemistichCounts() {
        let r = RevealState(index: index(), cursor: 3)   // a,b,c revealed; d not
        #expect(r.revealedWords(bayt: 1, half: .sadr) == 2)  // both sadr words
        #expect(r.revealedWords(bayt: 1, half: .ajuz) == 1)  // only "c"
    }

    @Test func zeroCursorRevealsNothing() {
        let r = RevealState(index: index(), cursor: 0)
        #expect(r.revealedWords(bayt: 1, half: .sadr) == 0)
    }

    // Two bayts: start indices must be recorded per (bayt, half) across the matn.
    private func twoBaytIndex() -> RecitationIndex {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: $0) })
        }
        let b1 = Bayt(number: 1, sadr: hemi(["a", "b"]), ajuz: hemi(["c", "d"]))   // indices 0-3
        let b2 = Bayt(number: 2, sadr: hemi(["e", "f"]), ajuz: hemi(["g", "h"]))   // indices 4-7
        let page = MatnPage(page: 1, items: [.bayt(b1), .bayt(b2)])
        return RecitationIndex(matn: Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t",
            author: "a", meter: "m", baytsPerPage: 2, pageCount: 1, baytCount: 2,
            pages: [page], babs: [], reviewNotes: []))
    }

    @Test func mapsAcrossMultipleBayts() {
        let r = RevealState(index: twoBaytIndex(), cursor: 6)  // bayt1 all; bayt2 sadr both (e,f), ajuz none
        #expect(r.revealedWords(bayt: 1, half: .ajuz) == 2)   // fully revealed earlier bayt
        #expect(r.revealedWords(bayt: 2, half: .sadr) == 2)   // e, f
        #expect(r.revealedWords(bayt: 2, half: .ajuz) == 0)   // not yet
    }

    @Test func clampsPastEndAndUnknownKeys() {
        let r = RevealState(index: index(), cursor: 999)      // way past the end
        #expect(r.revealedWords(bayt: 1, half: .ajuz) == 2)   // clamped to the hemistich's 2 words
        #expect(r.revealedWords(bayt: 99, half: .sadr) == 0)  // unknown bayt → 0
    }
}
