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
                    meter: "m", subject: .quran, kind: .poem, hadiths: [],
                    baytsPerPage: 1, pageCount: 1, baytCount: 1,
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

    /// The cover is page 0 and isn't in `pages`, so it has to seed from the top
    /// of the matn. It used to clamp to the end like an out-of-range page, which
    /// started a sitting with its cursor past the last word: the mic said it was
    /// listening and no recitation could ever match. The Duo's book view makes
    /// this the common path — the cover shares the opening spread with page 1.
    @Test func aSittingStartedOnTheCoverBeginsAtTheFirstWord() {
        let idx = RecitationIndex(matn: makeMatn())
        #expect(idx.firstWordIndex(onPage: 0) == 0)
        #expect(idx.firstWordIndex(onPage: 0) < idx.normalizedWords.count)
    }

    /// A page with only a bab heading on it has no words of its own; reciting
    /// "from here" means the next page's first word, not the end of the matn.
    @Test func aHeadingOnlyPageSeedsFromTheNextPageWithWords() {
        func hemi(_ words: [String]) -> Hemistich {
            Hemistich(text: words.joined(separator: " "),
                      segments: [Segment(text: words.joined(separator: " "), color: .black, footnote: nil)],
                      words: words.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) })
        }
        let heading = Heading(text: "باب", segments: [Segment(text: "باب", color: .black, footnote: nil)])
        let bayt = Bayt(number: 1, sadr: hemi(["يقول"]), ajuz: hemi(["عفو"]))
        let matn = Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                        meter: "m", subject: .quran, kind: .poem, hadiths: [],
                        baytsPerPage: 1, pageCount: 2, baytCount: 1,
                        pages: [MatnPage(page: 1, items: [.heading(heading)]),
                                MatnPage(page: 2, items: [.bayt(bayt)])],
                        babs: [], reviewNotes: [])
        let idx = RecitationIndex(matn: matn)
        #expect(idx.firstWordIndex(onPage: 1) == 0)
        #expect(idx.firstWordIndex(onPage: 0) == 0)
    }
}
