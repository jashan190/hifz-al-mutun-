import Testing
import Foundation
@testable import HifzAlMutun

/// Tanween or noon sakina into ي ر م ل و ن: right with idgham and without,
/// however Whisper spells it.
@Suite struct IdghamTests {
    /// Words said right on each side of the pair, so it's judged in place.
    private let before = ["سميته", "بتحفه"], after = ["الاطفال", "عن"]

    private func outcomes(_ written: (String, String), heard: [String])
        -> (first: WordOutcome?, second: WordOutcome?, tracker: RecitationTracker) {
        let shown = before + [written.0, written.1] + after
        let words = shown.map(ArabicNormalize.normalize)
        let t = RecitationTracker(words: words, idgham: Idgham.spellings(written: shown, words: words))
        t.consume(.init(text: (before + heard + after).joined(separator: " "), isFinal: true), at: 1)
        return (t.outcomes[2], t.outcomes[3], t)
    }

    @Test(arguments: [
        // Noon sakina.
        ["من", "يقول"], ["منيقول"], ["ميقول"], ["مييقول"], ["م", "يقول"], ["من", "ييقول"],
    ])
    func aNoonSakinaIsRightEitherWay(_ heard: [String]) {
        let r = outcomes(("مِنْ", "يَقُولُ"), heard: heard)
        #expect(r.first == .correct)
        #expect(r.second == .correct)
        #expect(r.tracker.cursor == 6)
        #expect(r.tracker.added.isEmpty)
    }

    @Test(arguments: [
        ["صغيرا", "يا"], ["صغير", "يا"], ["صغيرن", "يا"], ["صغير", "نيا"], ["صغيرا", "ييا"],
        ["صغيرايا"], ["صغيريا"], ["صغيرييا"], ["صغيرنيا"],
    ])
    func aTanweenWithItsAlifIsRightEitherWay(_ heard: [String]) {
        let r = outcomes(("صَغِيرًا", "يَا"), heard: heard)
        #expect(r.first == .correct)
        #expect(r.second == .correct)
        #expect(r.tracker.cursor == 6)
        #expect(r.tracker.added.isEmpty)
    }

    @Test(arguments: [
        ["محمد", "واله"], ["محمدن", "واله"], ["محمدواله"], ["محمدوواله"], ["محمدنواله"], ["محمد", "وواله"],
    ])
    func aTanweenWithoutAnAlifIsRightEitherWay(_ heard: [String]) {
        let r = outcomes(("مُحَمَّدٍ", "وَآلِهِ"), heard: heard)
        #expect(r.first == .correct)
        #expect(r.second == .correct)
        #expect(r.tracker.cursor == 6)
    }

    @Test func aMisheardLetterInAMergedPairIsStillChecked() {
        let r = outcomes(("صَغِيرًا", "يَا"), heard: ["سغيريا"])
        #expect(r.first == .unsure)
        #expect(r.second == .unsure)
        #expect(r.tracker.cursor == 6)
    }

    @Test func aWrongWordIsStillWrong() {
        let r = outcomes(("صَغِيرًا", "يَا"), heard: ["كتاب", "يا"])
        #expect(r.first == .wrong(heard: "كتاب"))
        #expect(r.second == .correct)
    }

    @Test func aSkippedWordIsStillSkipped() {
        let r = outcomes(("صَغِيرًا", "يَا"), heard: ["يا"])
        #expect(r.first == .skipped)
    }

    @Test func aShortTokenNearAMergedPairIsntThePair() {
        // عم is one letter from عما (عَنْ مَا merged): too little to go on.
        let r = outcomes(("عَنْ", "مَا"), heard: ["عم"])
        #expect(r.first == .unsure)
        #expect(r.second == .skipped)
    }

    @Test func aStrayLetterDoesntPassTheWord() {
        // م with no يقول after it: not مِنْ said, and nothing is passed over.
        let shown = ["مِنْ", "يَقُولُ", "كِتَابَهُ", "مِنْ", "يَقُولُ"]
        let words = shown.map(ArabicNormalize.normalize)
        let t = RecitationTracker(words: words, idgham: Idgham.spellings(written: shown, words: words))
        t.consume(.init(text: "من يقول م", isFinal: true), at: 1)
        #expect(t.cursor == 2)
        #expect(t.lastRight == 1)
    }

    @Test func aOneLetterSpellingNeedsTheNextWord() {
        // م then كتابه, يقول not said: مِنْ isn't shown right on a lone letter.
        let shown = ["سميته", "مِنْ", "يَقُولُ", "كِتَابَهُ"]
        let words = shown.map(ArabicNormalize.normalize)
        let t = RecitationTracker(words: words, idgham: Idgham.spellings(written: shown, words: words))
        t.consume(.init(text: "سميته م كتابه", isFinal: true), at: 1)
        #expect(t.outcomes[1] == .unsure)
        #expect(t.outcomes[2] == .skipped)
        #expect(t.outcomes[3] == .correct)
    }

    @Test func aMergedPairRefindsALostPlace() {
        let shown = ["سميته", "بتحفه", "الاطفال", "مِنْ", "يَقُولُ", "كِتَابَهُ"]
        let words = shown.map(ArabicNormalize.normalize)
        let t = RecitationTracker(words: words, idgham: Idgham.spellings(written: shown, words: words))
        t.consume(.init(text: "سميته شيء غريب جدا هنا", isFinal: true), at: 1)
        #expect(t.lockState == .lost)
        t.consume(.init(text: "ميقول", isFinal: true), at: 2)
        #expect(t.lockState == .locked)
        #expect(t.outcomes[2] == .unheard)
        #expect(t.outcomes[3] == .correct)
        #expect(t.outcomes[4] == .correct)
        #expect(t.cursor == 5)
    }

    @Test func wordsThatDontMergeArentLoosened() {
        // ب isn't an idgham letter, and قَالَ doesn't end in noon or tanween.
        let notBefore = outcomes(("صَغِيرًا", "بَعْدُ"), heard: ["صغير", "بعد"])
        #expect(notBefore.first == .unsure)
        let noEnding = outcomes(("قَالَ", "رَبُّهُ"), heard: ["قالن", "ربه"])
        #expect(noEnding.first == .unsure)
        let voweled = outcomes(("النُّونِ", "وَالتَّنْوِينِ"), heard: ["النو", "والتنوين"])
        #expect(voweled.first == .unsure)
    }

    @Test func spellingsComeFromTheWrittenEnding() {
        func forms(_ written: String, _ next: String) -> Set<String>? {
            Idgham.forms(written: written, word: ArabicNormalize.normalize(written),
                         next: ArabicNormalize.normalize(next)).map(Set.init)
        }
        #expect(forms("مِنْ", "يَقُولُ") == ["من", "م"])
        #expect(forms("صَغِيرًا", "يَا") == ["صغيرا", "صغير", "صغيرن"])
        #expect(forms("رَحْمَاناً", "رَحِيماً") == ["رحمانا", "رحمان", "رحمانن"])
        #expect(forms("مُحَمَّدٍ", "وَآلِهِ") == ["محمد", "محمدن"])
        #expect(forms("بِغُنَّةٍ", "مَعَ") == ["بغنه", "بغنهن", "بغنت", "بغنتن"])
        #expect(forms("مِنْ", "بَعْدُ") == nil)
        #expect(forms("النُّونِ", "وَالتَّنْوِينِ") == nil)
        #expect(forms("قَالَ", "رَبُّهُ") == nil)
    }

    @Test func theIndexFindsThemInARealPoem() throws {
        let url = try #require(Bundle.main.url(forResource: "tuhfa", withExtension: "json"))
        let matn = try JSONDecoder().decode(Matn.self, from: Data(contentsOf: url))
        let index = RecitationIndex(matn: matn)
        let pair = try #require(zip(index.displayWords, index.displayWords.dropFirst()).enumerated()
            .first { $0.element.0 == "مُحَمَّدٍ" && $0.element.1 == "وَآلِهِ" })
        #expect(Set(index.idgham[pair.offset] ?? []) == ["محمد", "محمدن"])
    }
}
