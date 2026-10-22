import Testing
import CoreGraphics
@testable import HifzAlMutun

@Suite struct ProsePaginatorTests {
    private func word(_ i: Int) -> ProseWord {
        ProseWord(text: "w\(i)", normalized: "w\(i)", role: .isnad)
    }
    private func hadith(_ n: Int, words: Int) -> Hadith {
        Hadith(number: n, title: "ح\(n)", body: (0..<words).map(word),
               takhrij: "رواه")
    }
    // Deterministic measure: each word is 1.0 tall (one word per "line").
    private let measure: ([ProseWord]) -> CGFloat = { CGFloat($0.count) }

    @Test func shortHadithIsOnePageBothFlags() {
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 3)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 1)
        let f = frag(pages[0])
        #expect(f.isFirst && f.isLast)
        #expect(f.words.count == 3)
        #expect(first[1] == 1)
    }

    @Test func longHadithSplitsAcrossPages() {
        // bodyHeight 10, heading 2 → first page fits 8 words, next pages 10.
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 15)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 2)
        #expect(frag(pages[0]).isFirst && !frag(pages[0]).isLast)
        #expect(!frag(pages[1]).isFirst && frag(pages[1]).isLast)
        let all = frag(pages[0]).words + frag(pages[1]).words
        #expect(all.map(\.text) == (0..<15).map { "w\($0)" })
        #expect(frag(pages[0]).words.count == 8)   // 10 - heading 2
        #expect(first[1] == 1)
    }

    @Test func secondHadithStartsFreshPage() {
        let (pages, first) = ProsePaginator.paginate(
            [hadith(1, words: 3), hadith(2, words: 2)],
            bodyHeight: 10, headingHeight: 2, takhrijHeight: 1, measureBody: measure)
        #expect(pages.count == 2)
        #expect(frag(pages[0]).hadithNumber == 1)
        #expect(frag(pages[1]).hadithNumber == 2)
        #expect(first[1] == 1 && first[2] == 2)
        #expect(pages[0].page == 1 && pages[1].page == 2)
    }

    private func frag(_ p: MatnPage) -> HadithFragment {
        guard case .hadith(let f) = p.items[0] else { fatalError("not a hadith page") }
        return f
    }
}
