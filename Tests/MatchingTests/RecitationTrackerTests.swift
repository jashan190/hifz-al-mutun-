import Testing
@testable import HifzAlMutun

@Suite struct RecitationTrackerTests {
    // Words are already normalized here for directness.
    private let words = ["يقول", "راجي", "عفو", "رب", "قادر", "محمد"]

    private func tracker() -> RecitationTracker {
        RecitationTracker(words: words, startIndex: 0,
                          window: 6, maxSkip: 3, lostAfter: 2.0)
    }

    @Test func perfectRecitationAdvancesWordByWord() {
        let t = tracker()
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        #expect(t.cursor == 1)
        #expect(t.lockState == .locked)
        t.consume(.init(text: "راجي", isFinal: true), at: 1)
        #expect(t.cursor == 2)
    }

    @Test func growingPartialsDoNotDoubleCount() {
        let t = tracker()
        t.consume(.init(text: "يقول", isFinal: false), at: 0)
        t.consume(.init(text: "يقول راجي", isFinal: false), at: 1)
        #expect(t.cursor == 2)   // not 3 — the repeated "يقول" is ignored
    }

    @Test func droppedWordIsSkipped() {
        let t = tracker()
        // Reciter says يقول … (راجي swallowed) … عفو
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        t.consume(.init(text: "عفو", isFinal: true), at: 1)
        #expect(t.cursor == 3)   // jumped over راجي
    }

    @Test func mishearToleratedByEditDistance() {
        let t = tracker()
        t.consume(.init(text: "يقيل", isFinal: true), at: 0)  // 1 substitution
        #expect(t.cursor == 1)
    }

    @Test func pauseGoesLostThenResyncs() {
        let t = tracker()
        t.consume(.init(text: "يقول راجي", isFinal: true), at: 0)
        #expect(t.cursor == 2)
        // Long silence, then an unmatched fragment: goes lost.
        t.consume(.init(text: "شيء غريب", isFinal: true), at: 5)
        #expect(t.lockState == .lost)
        // Reciter resumes further ahead; wide window re-locks.
        t.consume(.init(text: "محمد", isFinal: true), at: 6)
        #expect(t.cursor == 6)
        #expect(t.lockState == .locked)
    }

    @Test func resetMovesCursor() {
        let t = tracker()
        t.consume(.init(text: "يقول راجي", isFinal: true), at: 0)
        t.reset(to: 0)
        #expect(t.cursor == 0)
        #expect(t.lockState == .idle)
    }

    @Test func autoAdvancesOverEmptyExpectedWords() {
        let t = RecitationTracker(words: ["يقول", "", "راجي"], startIndex: 0,
                                  window: 6, maxSkip: 3, lostAfter: 2.0)
        t.consume(.init(text: "يقول", isFinal: true), at: 0)
        #expect(t.cursor == 2)   // skipped the empty slot, sits before راجي
        t.consume(.init(text: "راجي", isFinal: true), at: 1)
        #expect(t.cursor == 3)
    }
}
