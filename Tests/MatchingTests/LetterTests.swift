import Testing
import Foundation
@testable import HifzAlMutun

/// Mapping the matched letters back to the written word, so a mistake can be
/// shown on the letters (and their harakat) that differ.
@Suite struct LetterTests {
    @Test func eachLetterTakesItsHarakat() {
        let word = "مُحَمَّدٍۨ"
        let scalars = Array(word.unicodeScalars).map { String($0) }
        let ranges = ArabicNormalize.letterRanges(word)
        #expect(ranges.map { scalars[$0].joined() } == ["مُ", "حَ", "مَّ", "دٍۨ"])
    }

    @Test func foldedLettersStillMap() {
        // أ folds to ا, ة to ه; آ decomposes to ا + madda.
        #expect(ArabicNormalize.letterRanges("آمَنَةٌ").count == ArabicNormalize.normalize("آمَنَةٌ").count)
        #expect(ArabicNormalize.letterRanges("- أَوَّلَا") == [2..<4, 4..<7, 7..<9, 9..<10])
    }

    @MainActor @Test func everyWordOfEveryMatnMaps() {
        let store = ContentStore()
        store.load()
        for matn in store.matns {
            let index = RecitationIndex(matn: matn)
            for (word, norm) in zip(index.displayWords, index.normalizedWords) {
                #expect(ArabicNormalize.letterRanges(word).count == norm.count, "\(matn.id): \(word)")
            }
        }
    }

    @Test func differingLetters() {
        #expect(mismatchedLetters(expected: "كتابه", heard: "كتابه").isEmpty)
        #expect(mismatchedLetters(expected: "كتابه", heard: "كتبه") == [2])      // ا not heard
        #expect(mismatchedLetters(expected: "الناس", heard: "الناص") == [4])
        #expect(mismatchedLetters(expected: "قد", heard: "") == [0, 1])
    }
}

extension LetterTests {
    @Test func theMistakenLetterTakesItsHarakat() {
        // وَثَلَّثْتُ heard as وثلست: the ث with its sukun.
        let word = "وَثَلَّثْتُ"
        let scalars = Array(word.unicodeScalars).map { String($0) }
        let ranges = LetterEmphasis.ranges(written: word, heard: "وثلست")
        #expect(ranges.map { scalars[$0].joined() } == ["ثْ"])
    }
}
