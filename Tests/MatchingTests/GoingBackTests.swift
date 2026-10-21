import Testing
import Foundation
@testable import HifzAlMutun

/// The side tracker: going back to recite part of the text again (as in
/// Tarteel) moves the place back, and a mistake then said right is fixed.
@Suite struct GoingBackTests {
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

    @Test func nothingIsRightBeforeTheFirstWord() {
        let t = tracker()
        #expect(t.lastRight == nil)
        say(t, "يقول راجي")
        #expect(t.lastRight == 1)
        t.jump(to: 4, at: 2)
        #expect(t.lastRight == nil)
    }

    @Test func goingBackALineMovesThePlaceBack() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله", "يقول راجي عفو سامع")
        #expect(t.cursor == 4)
        #expect(t.lastRight == 3)
        #expect(!t.outcomes.values.contains { $0.isMistake })
    }

    @Test func aMistakeSaidRightAfterGoingBackIsFixed() {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله كتاب", "يقول راجي عفو سامع الحمد لله وصلي")
        #expect(t.outcomes[6] == .fixed(was: "كتاب"))
        #expect(t.outcomes[6]?.isMistake == false)
        #expect(t.outcomes[6]?.flagsWord == true)     // still reviewed later
        #expect(t.lastRight == 6)
    }

    @Test func theWordDueWhileGoingBackIsntAMistake() {
        // Streamed as the guess grows: وصلي may show red at the first word
        // that doesn't fit, and is cleared once going back is clear.
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله")
        var guess = ""
        for (k, word) in ["يقول", "راجي", "عفو", "سامع"].enumerated() {
            guess += (guess.isEmpty ? "" : " ") + word
            t.consume(.init(text: guess, isFinal: false), at: Double(10 + k))
        }
        #expect(t.shownOutcomes[6] == nil)
        t.consume(.init(text: guess, isFinal: true), at: 20)
        #expect(t.outcomes[6] == nil)
        #expect(!t.outcomes.values.contains { $0.isMistake })
    }

    @Test(arguments: ["سامع الحمد", "عفو سامع الحمد"])
    func repeatingAFewWordsIsStillIgnored(_ repeated: String) {
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد \(repeated) لله وصلي")
        #expect(t.cursor == 7)
        #expect(t.outcomes == [0: .correct, 1: .correct, 2: .correct, 3: .correct,
                               4: .correct, 5: .correct, 6: .correct])
    }

    @Test func goingBackMoreThanABaytIsntFollowed() {
        // From the third bayt, the first is two bayts back.
        let t = tracker()
        say(t, "يقول راجي عفو سامع الحمد لله وصلي علي نبيه", "يقول راجي عفو سامع")
        #expect(t.cursor > 8)
        #expect(t.lastRight == 8)
    }
}
