import Testing
import Foundation
@testable import HifzAlMutun

/// A bayt left out whole: the tracker finds the reciter again further on,
/// the words said meanwhile count as right, and the bayt is one mistake.
@MainActor @Suite struct SkippedBaytTests {
    private static func tuhfa() throws -> RecitationIndex {
        let store = ContentStore()
        store.load()
        return RecitationIndex(matn: try #require(store.matns.first { $0.id == "tuhfa" }))
    }

    /// As the app builds it.
    private func tracker(_ index: RecitationIndex) -> RecitationTracker {
        RecitationTracker(words: index.normalizedWords, startIndex: 0, bayts: index.refs.map(\.bayt),
                          idgham: index.idgham, prose: index.isProse)
    }

    /// Each bayt in `bayts` recited correctly, one final per bayt.
    private func recite(_ bayts: [Int], into t: RecitationTracker, _ index: RecitationIndex) {
        for (k, b) in bayts.enumerated() {
            let text = index.refs.indices.filter { index.refs[$0].bayt == b }
                .map { index.normalizedWords[$0] }.filter { !$0.isEmpty }.joined(separator: " ")
            t.consume(.init(text: text, isFinal: true), at: Double(k))
        }
    }

    private func words(of bayts: ClosedRange<Int>, _ index: RecitationIndex) -> [Int] {
        index.refs.indices.filter { bayts.contains(index.refs[$0].bayt) && !index.normalizedWords[$0].isEmpty }
    }

    @Test func aSkippedBaytIsFoundAgainAndCountsOnce() throws {
        let index = try Self.tuhfa()
        let t = tracker(index)
        recite([1, 2, 3, 4, 5, 6, 7, 9, 10], into: t, index)
        #expect(words(of: 8...8, index).allSatisfy { t.outcomes[$0] == .skipped })
        #expect(words(of: 9...10, index).allSatisfy { t.outcomes[$0] == .correct },
                "\(words(of: 9...10, index).map { t.outcomes[$0].map { "\($0)" } ?? "-" })")
        #expect(index.skippedBayts(t.outcomes) == [8])
        #expect(index.mistakeCount(t.outcomes) == 1)
        #expect(t.cursor == index.firstWordIndex(ofBayt: 11))
        let eight = try #require(index.firstWordIndex(ofBayt: 8))
        #expect(t.withdrawn.isSubset(of: [eight]))
    }

    @Test func aWrongBaytIsNotASkip() throws {
        // Words that aren't the text at all, then the next bayt: the word due
        // stays wrong, and nothing is grouped as skipped.
        let index = try Self.tuhfa()
        let t = tracker(index)
        recite([1], into: t, index)
        t.consume(.init(text: "كتاب قلم مدرسة بيت", isFinal: true), at: 1)
        recite([3, 4], into: t, index)
        let due = try #require(index.firstWordIndex(ofBayt: 2))
        #expect(t.outcomes[due]?.isMistake == true)
        #expect(index.skippedBayts(t.outcomes).isEmpty)
        #expect(words(of: 3...4, index).allSatisfy { t.outcomes[$0] == .correct })
    }

    @Test func aCorrectRecitationIsUnchanged() throws {
        let index = try Self.tuhfa()
        let t = tracker(index)
        recite(Array(1...12), into: t, index)
        #expect(!t.outcomes.values.contains { $0.isMistake })
        #expect(t.cursor == index.firstWordIndex(ofBayt: 13))
    }
}
