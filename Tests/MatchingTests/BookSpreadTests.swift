import Testing
import CoreGraphics
@testable import HifzAlMutun

/// The open iPhone Duo on its side: pages in fixed pairs, like a book.
@Suite struct BookSpreadTests {
    @Test func pagesPairOneTwoThreeFour() {
        #expect([0, 1, 2, 3, 4, 5].map(BookSpread.first(of:)) == [0, 1, 1, 3, 3, 5])
    }

    @Test func theTitlePageStandsAlone() {
        #expect(BookSpread.pages(of: 0, pageCount: 9) == [0])
        #expect(BookSpread.spreads(pageCount: 5) == [0, 1, 3, 5])
    }

    @Test func anOddLastPageHasABlankBesideIt() {
        #expect(BookSpread.pages(of: 3, pageCount: 4) == [3, 4])
        #expect(BookSpread.pages(of: 5, pageCount: 5) == [5, nil])
    }

    @Test func onlyTheInnerScreenOpensAsABook() {
        #expect(BookSpread.isInnerScreen(phone: true, regularWidth: true, regularHeight: true))
        // A Pro Max on its side; any iPhone upright; an iPad.
        #expect(!BookSpread.isInnerScreen(phone: true, regularWidth: true, regularHeight: false))
        #expect(!BookSpread.isInnerScreen(phone: true, regularWidth: false, regularHeight: true))
        #expect(!BookSpread.isInnerScreen(phone: false, regularWidth: true, regularHeight: true))
    }

    @Test func theHadithPlaceIsKeptWhenPagesAreCutAgain() {
        let hadiths = [Hadith(number: 1, title: "١", body: (0..<12).map { ProseWord(text: "كلمة\($0)", normalized: "كلمة", role: .isnad) }, takhrij: ""),
                       Hadith(number: 2, title: "٢", body: (0..<12).map { ProseWord(text: "قول\($0)", normalized: "قول", role: .matn) }, takhrij: "")]
        func cut(_ perPage: Int) -> [MatnPage] {
            ProsePaginator.paginate(hadiths, bodyHeight: CGFloat(perPage), headingHeight: 0, takhrijHeight: 0,
                                    measureBody: { CGFloat($0.count) }).pages
        }
        let folded = cut(4), open = cut(6)
        // Folded, page 5 starts at hadith 2's word 4; open, that's on page 3.
        let place = try! #require(ProsePaginator.place(onPage: 5, in: folded))
        #expect(place.hadith == 2 && place.wordInBody == 4)
        #expect(ProsePaginator.page(holding: 2, wordInBody: 4, in: open) == 3)
        #expect(ProsePaginator.page(holding: 3, wordInBody: 0, in: open) == nil)
    }
}
