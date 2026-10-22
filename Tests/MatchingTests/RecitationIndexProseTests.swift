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

    @Test func emptyBodyHandledGracefully() {
        // The builder rejects empty bodies, but the index shouldn't crash on one:
        // the hadith gets a valid (empty) start and contributes no words.
        let h = Hadith(number: 1, title: "", body: [], takhrij: "")
        let m = Matn(id: "p", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                     meter: "", subject: .hadith, kind: .prose, hadiths: [h],
                     baytsPerPage: 0, pageCount: 0, baytCount: 1, pages: [], babs: [], reviewNotes: [])
        let index = RecitationIndex(matn: m)
        #expect(index.normalizedWords.isEmpty)
        #expect(index.firstWordIndex(ofBayt: 1) == 0)   // valid start, spans nothing
    }

    @Test func poemIndexUnchanged() {
        // A bayt poem still flattens sadr-then-ajuz, page 1, with real refs. (The
        // poem path re-normalizes word.text at runtime by design, so assert the
        // display text + structure, not Latin normalization.)
        let bayt = Bayt(number: 1,
                        sadr: Hemistich(text: "فِي النَّظْمِ", segments: [], words: [Word(text: "فِي", normalized: "في"), Word(text: "النَّظْمِ", normalized: "النظم")]),
                        ajuz: Hemistich(text: "أَوَّلَا", segments: [], words: [Word(text: "أَوَّلَا", normalized: "اولا")]))
        let page = MatnPage(page: 1, items: [.bayt(bayt)])
        let m = Matn(id: "q", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                     meter: "الرجز", subject: .quran, kind: .poem, hadiths: [],
                     baytsPerPage: 10, pageCount: 1, baytCount: 1, pages: [page], babs: [], reviewNotes: [])
        let index = RecitationIndex(matn: m)
        #expect(index.displayWords == ["فِي", "النَّظْمِ", "أَوَّلَا"])
        #expect(index.normalizedWords.count == 3)
        #expect(index.refs.map(\.half) == [.sadr, .sadr, .ajuz])
        #expect(index.refs.map(\.page) == [1, 1, 1])
    }
}
