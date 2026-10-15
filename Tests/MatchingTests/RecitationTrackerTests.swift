import Testing
@testable import HifzAlMutun

@Suite struct RecitationTrackerTests {
    // Words are already normalized here for directness.
    private let words = ["يقول", "راجي", "عفو", "رب", "قادر", "محمد"]

    private func tracker(_ words: [String]? = nil) -> RecitationTracker {
        RecitationTracker(words: words ?? self.words, startIndex: 0,
                          tuning: MatchTuning(lockedLookahead: 4, lostWindow: 6, lostAfter: 2.0))
    }

    private func final(_ t: RecitationTracker, _ text: String, at time: Double = 0) {
        t.consume(.init(text: text, isFinal: true), at: time)
    }

    // MARK: - Following along

    @Test func perfectRecitationAdvancesWordByWord() {
        let t = tracker()
        final(t, "يقول")
        #expect(t.cursor == 1)
        #expect(t.lockState == .locked)
        final(t, "راجي")
        #expect(t.cursor == 2)
        #expect(t.outcomes[0] == .correct && t.outcomes[1] == .correct)
    }

    @Test func growingPartialsDoNotDoubleCount() {
        let t = tracker()
        t.consume(.init(text: "يقول", isFinal: false), at: 0)
        t.consume(.init(text: "يقول راجي", isFinal: false), at: 1)
        #expect(t.cursor == 2)   // not 3 — the repeated "يقول" is ignored
        #expect(t.outcomes.isEmpty)   // volatile results are never judged
    }

    // A volatile result is replaced by the next one for the same audio, so a
    // repeated hypothesis can't walk over two identical consecutive words.
    @Test func repeatedHypothesisDoesNotPassIdenticalWords() {
        let t = tracker(["قال", "قال", "رب"])
        t.consume(.init(text: "قال", isFinal: false), at: 0)
        t.consume(.init(text: "قال", isFinal: false), at: 1)
        #expect(t.cursor == 1)
        final(t, "قال قال", at: 2)
        #expect(t.cursor == 2)
    }

    @Test func volatileMishearingCorrectedBeforeFinalIsNotAMistake() {
        let t = tracker()
        final(t, "يقول")
        t.consume(.init(text: "شيء", isFinal: false), at: 1)   // misheard partial…
        t.consume(.init(text: "راجي", isFinal: false), at: 2)  // …revised
        final(t, "راجي", at: 3)
        #expect(t.outcomes[1] == .correct)
        #expect(!t.outcomes.values.contains { $0.isMistake })
    }

    @Test func autoAdvancesOverEmptyExpectedWords() {
        let t = tracker(["يقول", "", "راجي"])
        final(t, "يقول")
        #expect(t.cursor == 2)   // skipped the empty slot, sits before راجي
        final(t, "راجي")
        #expect(t.cursor == 3)
    }

    @Test func resetMovesCursor() {
        let t = tracker()
        final(t, "يقول راجي")
        t.reset(to: 0)
        #expect(t.cursor == 0)
        #expect(t.lockState == .idle)
        #expect(t.outcomes.isEmpty)
    }

    // MARK: - Judging words

    @Test func droppedWordIsSkipped() {
        let t = tracker()
        final(t, "يقول")
        final(t, "عفو")              // راجي passed over between two recited words
        #expect(t.cursor == 3)
        #expect(t.outcomes[1] == .skipped)
        #expect(t.outcomes[2] == .correct)
    }

    @Test func substitutedWordIsWrongWithWhatWasHeard() {
        let t = tracker()
        final(t, "يقول")
        final(t, "سلام")             // said instead of راجي
        final(t, "عفو")
        #expect(t.outcomes[1] == .wrong(heard: "سلام"))
        #expect(t.outcomes[2] == .correct)
    }

    @Test func nearMissSubstitutionIsUnsureNotWrong() {
        let t = tracker()
        final(t, "يقول")
        final(t, "راجوا")            // too far for a match, close enough to be a mishearing
        final(t, "عفو")
        #expect(t.outcomes[1] == .unsure)
    }

    @Test func fuzzyMatchIsUnsure() {
        let t = tracker()
        final(t, "يقيل")             // 1 substitution
        #expect(t.cursor == 1)
        #expect(t.outcomes[0] == .unsure)
    }

    @Test func shortWordsMustMatchExactly() {
        let t = tracker(["في", "رب"])
        final(t, "فن")               // one letter off a two-letter word
        #expect(t.cursor == 0)
    }

    @Test func extraWordsAreNotFlagged() {
        let t = tracker()
        final(t, "يقول هذا راجي")
        #expect(t.cursor == 2)
        #expect(!t.outcomes.values.contains { $0.isMistake })
    }

    // MARK: - Losing and re-finding the place

    @Test func pauseGoesLostThenResyncsFarAhead() {
        let t = tracker()
        final(t, "يقول", at: 0)
        // Long silence, then an unmatched final result: goes lost.
        final(t, "شيء غريب", at: 5)
        #expect(t.lockState == .lost)
        // Reciter resumes beyond the nearby window; the wide window re-locks.
        final(t, "محمد", at: 6)
        #expect(t.cursor == 6)
        #expect(t.lockState == .locked)
        // The words jumped while lost may just not have been heard: not mistakes.
        #expect(t.outcomes[1] == .unheard && t.outcomes[4] == .unheard)
    }

    // A pause alone doesn't lose the place: a word skipped right after it is
    // still a skip, judged as if locked.
    @Test func skipAfterAPauseIsStillASkip() {
        let t = tracker()
        final(t, "يقول", at: 0)
        final(t, "شي", at: 3)          // a final fragment after the pause
        #expect(t.lockState == .lost)
        final(t, "عفو", at: 3.5)
        #expect(t.cursor == 3)
        #expect(t.outcomes[1] == .wrong(heard: "شي"))
    }

    // A volatile fragment after a pause must not change how the following
    // final result is judged.
    @Test func volatileAfterAPauseDoesNotLoseThePlace() {
        let t = tracker()
        final(t, "يقول", at: 0)
        t.consume(.init(text: "شي", isFinal: false), at: 3)
        final(t, "عفو", at: 3.5)
        #expect(t.cursor == 3)
        #expect(t.lockState == .locked)
        #expect(t.outcomes[1] == .skipped)
    }

    @Test func manyUnmatchedWordsGoLost() {
        let t = tracker()
        final(t, "يقول")
        final(t, "شيء غريب جدا هنا")  // 4 unmatched tokens
        #expect(t.lockState == .lost)
    }

    @Test func lostNeedsStrongEvidenceToResync() {
        let t = tracker()
        final(t, "يقول", at: 0)
        final(t, "شيء غريب جدا هنا", at: 1)   // what's heard doesn't fit: lost
        #expect(t.lockState == .lost)
        final(t, "رب", at: 2)        // a short word alone isn't enough
        #expect(t.cursor == 1)
        final(t, "رب قادر", at: 3)   // …but followed by the next word, it is
        #expect(t.cursor == 5)
    }

    @Test func wordsBeforeTheFirstMatchAreUnheard() {
        let t = tracker()
        final(t, "عفو")              // the recognizer missed the opening words
        #expect(t.cursor == 3)
        #expect(t.outcomes[0] == .unheard && t.outcomes[1] == .unheard)
    }
}
