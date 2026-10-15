import Testing
import Foundation
@testable import HifzAlMutun

/// How the tracker copes with the way Whisper writes recitation (prefixes
/// joined to the next word, a word split in two), and how soon a mistake shows.
@Suite struct TrackerAccuracyTests {
    private func tracker(_ words: [String]) -> RecitationTracker {
        RecitationTracker(words: words, startIndex: 0)
    }

    // MARK: - Joined and split words

    @Test func aPrefixWrittenApartMatchesWhenHeardJoined() {
        // بِـ: بِسْمِ اللهِ — the text writes the ب apart; it's recited, and
        // transcribed, as ببسم.
        let t = tracker(["بدات", "ب", "بسم", "الله"])
        t.consume(.init(text: "بدأت ببسم الله", isFinal: true), at: 0)
        #expect(t.cursor == 4)
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct, 3: .correct])
    }

    @Test func aLongWordIsNeverAbsorbedIntoAJoin() {
        // "رب" + "قادر" joined doesn't stand for a skipped "عفو".
        let t = tracker(["يقول", "عفو", "رب", "قادر"])
        t.consume(.init(text: "يقول رب قادر", isFinal: true), at: 0)
        #expect(t.outcomes[1] == .skipped)
        #expect(t.outcomes[2] == .correct)
    }

    @Test func aWordHeardAsTwoTokensMatches() {
        let t = tracker(["قال", "مرتضاه", "هو"])
        t.consume(.init(text: "قال مر تضاه هو", isFinal: true), at: 0)
        #expect(t.cursor == 3)
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct])
    }

    @Test func aDroppedLoneLetterIsUnsureNotRed() {
        // The recognizer often drops a lone letter; check it, don't fail it.
        let t = tracker(["بدات", "ب", "بسم", "الله"])
        t.consume(.init(text: "بدأت بسم الله", isFinal: true), at: 0)
        #expect(t.outcomes[1] == .unsure)
        #expect(t.outcomes[2] == .correct)
    }

    // MARK: - Showing mistakes from the guess

    @Test func aMistakeShowsOnceTwoGuessesAgree() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول عفو", isFinal: false), at: 0)
        #expect(t.shownOutcomes[1] == nil)               // one guess: could still change
        t.consume(.init(text: "يقول عفو رب", isFinal: false), at: 1)
        #expect(t.shownOutcomes[1] == .skipped)          // two agree: shown
        #expect(t.outcomes.isEmpty)                      // but not kept until final
        t.consume(.init(text: "يقول عفو رب", isFinal: true), at: 2)
        #expect(t.outcomes[1] == .skipped)
    }

    @Test func aMistakeFollowedByTwoWordsShowsAtOnce() {
        let t = tracker(["يقول", "راجي", "عفو", "رب", "قادر"])
        t.consume(.init(text: "يقول عفو رب", isFinal: false), at: 0)
        #expect(t.shownOutcomes[1] == .skipped)          // عفو رب both follow it
        #expect(t.outcomes.isEmpty)
    }

    @Test func aGuessCorrectedBeforeItSettlesNeverShows() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول عفو", isFinal: false), at: 0)
        t.consume(.init(text: "يقول راجي عفو", isFinal: false), at: 1)   // the recognizer fixed it
        #expect(t.shownOutcomes[1] == .correct || t.shownOutcomes[1] == nil)
        #expect(!t.shownOutcomes.values.contains { $0.isMistake })
    }

    @Test func notAMistakeOnAShownGuessSurvivesTheFinal() {
        let t = tracker(["يقول", "راجي", "عفو", "رب"])
        t.consume(.init(text: "يقول عفو", isFinal: false), at: 0)
        t.consume(.init(text: "يقول عفو رب", isFinal: false), at: 1)
        t.override(1, with: .correct)
        #expect(t.shownOutcomes[1] == .correct)
        t.consume(.init(text: "يقول عفو رب", isFinal: true), at: 2)
        #expect(t.outcomes[1] == .correct)
    }

    // MARK: - All three mutun

    @MainActor private static func allMatns() -> [Matn] {
        let store = ContentStore()
        store.load()
        return store.matns
    }

    /// Every word recited correctly, one final per hemistich: no mistakes —
    /// both token for token, and the way Whisper writes it (each lone letter
    /// joined to the word after it).
    @MainActor @Test(arguments: [false, true])
    func perfectRecitationOfEveryMatnHasNoMistakes(whisperStyle: Bool) {
        let matns = Self.allMatns()
        #expect(matns.count == 3)
        for matn in matns {
            let index = RecitationIndex(matn: matn)
            let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
            var line: [String] = []
            var carry = ""
            for (i, word) in index.normalizedWords.enumerated() {
                if whisperStyle, word.count == 1 { carry += word; continue }
                line.append(carry + word)
                carry = ""
                let endOfHalf = i + 1 == index.refs.count
                    || index.refs[i + 1].half != index.refs[i].half
                    || index.refs[i + 1].bayt != index.refs[i].bayt
                if endOfHalf {
                    t.consume(.init(text: line.joined(separator: " "), isFinal: true), at: Double(i))
                    line = []
                }
            }
            let mistakes = t.outcomes.filter { $0.value.isMistake }
            #expect(mistakes.isEmpty, "\(matn.id): \(mistakes.count) false mistakes, e.g. \(mistakes.sorted { $0.key < $1.key }.prefix(5))")
            #expect(t.cursor == index.normalizedWords.count, "\(matn.id) stopped at \(t.cursor)")
        }
    }

    // MARK: - How soon a mistake shows

    /// Mistakes put into the real Whisper transcript of the clip, replayed the
    /// way the streamer delivers it. Counts the updates from the one that first
    /// holds the word after the mistake (the earliest it can be judged) until
    /// the mistake shows.
    @Test func mistakesShowWithinOneUpdateOfTheNextWord() throws {
        let index = try WhisperTests.shatibiyya()
        var heard = WhisperTests.turboTranscript.split(separator: " ").map(String.init)
        // Skip "الناس" (index 24 of the transcript) and say "قلبه" for "كتابه".
        let skipped = try #require(heard.firstIndex(of: "الناس"))
        heard.remove(at: skipped)
        let swapped = try #require(heard.firstIndex(of: "كتابه"))
        heard[swapped] = "قلبه"

        let t = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        let targets = [
            (word: try #require(index.normalizedWords.firstIndex(of: "الناس")), heardAfter: skipped),
            (word: try #require(index.normalizedWords.firstIndex(of: "كتابه")), heardAfter: swapped + 1),
        ]
        var firstHeard: [Int: Int] = [:]   // target word → update holding the word after it
        var shownAt: [Int: Int] = [:]
        var keptAt: [Int: Int] = [:]
        var update = 0
        WhisperTests.stream(heard.joined(separator: " "), into: t) { wordsHeard in
            update += 1
            for target in targets {
                if firstHeard[target.word] == nil, wordsHeard > target.heardAfter { firstHeard[target.word] = update }
                if shownAt[target.word] == nil, t.shownOutcomes[target.word]?.isMistake == true { shownAt[target.word] = update }
                if keptAt[target.word] == nil, t.outcomes[target.word]?.isMistake == true { keptAt[target.word] = update }
            }
        }
        for target in targets {
            let heardAt = try #require(firstHeard[target.word])
            let shown = try #require(shownAt[target.word], "word \(target.word) never shown")
            let kept = try #require(keptAt[target.word])
            print("LATENCY word \(target.word): shown \(shown - heardAt) updates after the next word, finalized \(kept - heardAt)")
            #expect(shown - heardAt <= 1)
            #expect(shown <= kept)
        }
    }
}
