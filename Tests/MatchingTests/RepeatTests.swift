import Testing
import Foundation
@testable import HifzAlMutun

/// Repeating text already said (the first try counts): a repeat moves the
/// place but never changes a judged word, except a mistake now said right,
/// which is fixed.
@Suite struct RepeatTests {
    // Three bayts of four words each.
    private let words = ["يقول", "راجي", "عفو", "سامع",
                         "الحمد", "لله", "وصلي", "علي",
                         "نبيه", "ومصطفاه", "وبعد", "هذا"]
    private let bayts = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3]

    private func tracker() -> RecitationTracker {
        RecitationTracker(words: words, startIndex: 0, bayts: bayts)
    }

    private func say(_ t: RecitationTracker, _ finals: String...) {
        for (k, text) in finals.enumerated() { t.consume(.init(text: text, isFinal: true), at: Double(k)) }
    }

    private var allRight: [Int: WordOutcome] {
        Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, WordOutcome.correct) })
    }

    @Test func wordsSaidRightStayRightAfterARepeat() {
        // The first bayt said again, then on from where they were, without
        // saying الحمد لله a second time.
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "يقول راجي عفو سامع", "وصلي علي")
        #expect(t.outcomes == allRight)
        #expect(t.added.isEmpty)
    }

    @Test func threeWordsFromFurtherBackAreARepeat() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "راجي عفو سامع", "الحمد لله وصلي علي")
        #expect(t.outcomes == allRight)
        #expect(t.added.isEmpty)
    }

    @Test func aMisheardWordInARepeatIsntAMistake() {
        // راجي heard as ماجد: the word due (وصلي) isn't called wrong for it.
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "يقول ماجد عفو سامع الحمد لله وصلي علي")
        #expect(t.outcomes == allRight)
        #expect(t.added.isEmpty)
    }

    @Test func aRepeatHeardNearlyDoesntDowngradeAWord() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "يقول راجي عفو سامح", "الحمد لله")
        #expect(t.outcomes[3] == .correct)
    }

    @Test func aMistakeSaidRightOnARepeatIsFixed() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله كتاب", "يقول راجي عفو سامع الحمد لله وصلي")
        #expect(t.outcomes[6] == .fixed(was: "كتاب"))
    }

    @Test func aMistakeStaysAMistakeIfTheRepeatGetsItWrongToo() {
        let t = tracker()
        say(t, "يقول راجي كتاب سامع الحمد لله", "يقول راجي قلم سامع الحمد لله")
        #expect(t.outcomes[2] == .wrong(heard: "كتاب"))
    }

    @Test func anEarlierMistakeIsntClearedByARepeat() {
        // Judged before the repeat began: still red, not removed.
        let t = tracker()
        say(t, "يقول راجي كتاب سامع الحمد لله", "راجي عفو سامع الحمد")
        #expect(t.outcomes[2] == .fixed(was: "كتاب"))
        #expect(t.outcomes[2]?.flagsWord == true)
    }

    @Test func newWordsAfterARepeatAreStillJudged() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "يقول راجي عفو سامع", "الحمد لله كتاب علي")
        #expect(t.outcomes[6] == .wrong(heard: "كتاب"))
    }
}
