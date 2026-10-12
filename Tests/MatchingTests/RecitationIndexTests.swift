import Testing
@testable import HifzAlMutun

@Suite struct RecitationIndexTests {
    // Build a tiny 1-page, 1-bayt matn inline.
    private func makeMatn() -> Matn {
        func hemi(_ words: [String]) -> Hemistich {
            Hemistich(
                text: words.joined(separator: " "),
                segments: [Segment(text: words.joined(separator: " "), color: .black, footnote: nil)],
                words: words.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) }
            )
        }
        let bayt = Bayt(number: 1, sadr: hemi(["يقول", "راجي"]), ajuz: hemi(["عفو", "رب"]))
        let page = MatnPage(page: 1, items: [.bayt(bayt)])
        return Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
                    pages: [page], babs: [], reviewNotes: [])
    }

    @Test func flattensSadrThenAjuz() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.normalizedWords == ["يقول", "راجي", "عفو", "رب"])
    }

    @Test func refsPointBackToLocation() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.refs[0].page == 1)
        #expect(idx.refs[0].bayt == 1)
        #expect(idx.refs[0].half == .sadr)
        #expect(idx.refs[0].wordIndex == 0)
        #expect(idx.refs[2].half == .ajuz)
        #expect(idx.refs[2].wordIndex == 0)
    }

    @Test func firstWordIndexOnPage() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.firstWordIndex(onPage: 1) == 0)
        #expect(idx.firstWordIndex(onPage: 99) == idx.normalizedWords.count) // past the end
    }
}
