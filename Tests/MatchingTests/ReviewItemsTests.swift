import Testing
@testable import HifzAlMutun

@Suite struct ReviewItemsTests {
    private func poemMatn() -> Matn {
        let b1 = Bayt(number: 1,
            sadr: Hemistich(text: "في النظم", segments: [], words: [Word(text:"في",normalized:"في"), Word(text:"النظم",normalized:"النظم")]),
            ajuz: Hemistich(text: "أولا", segments: [], words: [Word(text:"أولا",normalized:"اولا")]))
        let b2 = Bayt(number: 2,
            sadr: Hemistich(text: "ثم بعد", segments: [], words: [Word(text:"ثم",normalized:"ثم"), Word(text:"بعد",normalized:"بعد")]),
            ajuz: Hemistich(text: "تلا", segments: [], words: [Word(text:"تلا",normalized:"تلا")]))
        let page = MatnPage(page: 1, items: [.bayt(b1), .bayt(b2)])
        return Matn(id: "p", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "الرجز", subject: .quran, kind: .poem, hadiths: [],
                    baytsPerPage: 10, pageCount: 1, baytCount: 2, pages: [page], babs: [], reviewNotes: [])
    }
    private func proseMatn() -> Matn {
        let h1 = Hadith(number: 1, title: "الحديث الأول",
            body: [ProseWord(text:"عَنْ",normalized:"عن",role:.isnad), ProseWord(text:"إِنَّمَا",normalized:"انما",role:.matn)],
            takhrij: "")
        return Matn(id: "q", title: "t", fullTitle: nil, titleLatin: "t", author: "a",
                    meter: "", subject: .hadith, kind: .prose, hadiths: [h1],
                    baytsPerPage: 0, pageCount: 0, baytCount: 1, pages: [], babs: [], reviewNotes: [])
    }

    @Test func resolvesPoemFlagsToWordAndLocationInReadingOrder() {
        let flags: Set<FlagKey> = [
            FlagKey(bayt: 2, half: .sadr, wordIndex: 1),
            FlagKey(bayt: 1, half: .ajuz, wordIndex: 0),
            FlagKey(bayt: 1, half: .sadr, wordIndex: 0),
        ]
        let items = ReviewItems.resolve(matn: poemMatn(), flags: flags)
        #expect(items.map(\.word) == ["في", "أولا", "بعد"])
        #expect(items[0].location == "Bayt 1 · first half")
        #expect(items[1].location == "Bayt 1 · second half")
        #expect(items[2].location == "Bayt 2 · first half")
    }

    @Test func resolvesProseFlagToHadithWord() {
        let items = ReviewItems.resolve(matn: proseMatn(),
            flags: [FlagKey(bayt: 1, half: .sadr, wordIndex: 1)])
        #expect(items.count == 1)
        #expect(items[0].word == "إِنَّمَا")
        #expect(items[0].location == "الحديث ١")
    }

    @Test func skipsOrphanOutOfRangeKeys() {
        let items = ReviewItems.resolve(matn: poemMatn(),
            flags: [FlagKey(bayt: 99, half: .sadr, wordIndex: 0),
                    FlagKey(bayt: 1, half: .sadr, wordIndex: 9)])
        #expect(items.isEmpty)
    }

    @Test func annotationMapKeysByPosition() {
        let m = ReviewSummary.Mistake(id: 0, page: 1, bayt: 2, half: .ajuz,
                                      wordIndex: 0, expected: "تلا", heard: "تلى")
        let map = ReviewItems.annotations(ReviewSummary(baytsRecited: 1, revealed: 0, mistakes: [m]))
        #expect(map[FlagKey(bayt: 2, half: .ajuz, wordIndex: 0)]?.heard == "تلى")
    }
}
