import Testing
@testable import HifzAlMutun

@Suite struct RecitationIndexProseTests {
    private func proseMatn() -> Matn {
        let h1 = Hadith(number: 1, title: "الحديث الأول",
                        body: [ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
                               ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn)],
                        takhrij: "رواه")
        let h2 = Hadith(number: 2, title: "الحديث الثاني",
                        body: [ProseWord(text: "بَيْنَمَا", normalized: "بينما", role: .matn)],
                        takhrij: "")
        return Matn(id: "p", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "", subject: .hadith, kind: .prose, hadiths: [h1, h2],
                    baytsPerPage: 0, pageCount: 0, baytCount: 2, pages: [], babs: [], reviewNotes: [])
    }

    @Test func flattensHadithBodiesInOrder() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.normalizedWords == ["عن", "انما", "بينما"])
        #expect(index.displayWords == ["عَنْ", "إِنَّمَا", "بَيْنَمَا"])
    }

    @Test func refsCarryHadithAsBaytAndWordInBody() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.refs.map(\.bayt) == [1, 1, 2])          // hadith number
        #expect(index.refs.allSatisfy { $0.half == .sadr })    // single half
        #expect(index.refs.map(\.wordIndex) == [0, 1, 0])      // index within body
    }

    @Test func firstWordIndexOfHadith() {
        let index = RecitationIndex(matn: proseMatn())
        #expect(index.firstWordIndex(ofBayt: 1) == 0)   // bayt == hadith number
        #expect(index.firstWordIndex(ofBayt: 2) == 2)
    }

    @Test func poemIndexUnchanged() {
        let bayt = Bayt(number: 1,
                        sadr: Hemistich(text: "a b", segments: [], words: [Word(text: "a", normalized: "a"), Word(text: "b", normalized: "b")]),
                        ajuz: Hemistich(text: "c", segments: [], words: [Word(text: "c", normalized: "c")]))
        let page = MatnPage(page: 1, items: [.bayt(bayt)])
        let m = Matn(id: "q", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                     meter: "الرجز", subject: .quran, kind: .poem, hadiths: [],
                     baytsPerPage: 10, pageCount: 1, baytCount: 1, pages: [page], babs: [], reviewNotes: [])
        let index = RecitationIndex(matn: m)
        #expect(index.normalizedWords == ["a", "b", "c"])
        #expect(index.refs.map(\.half) == [.sadr, .sadr, .ajuz])
    }
}
