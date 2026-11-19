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

    // Skips of one to three bayts, from a few places: each found again, the
    // bayts left out grouped, nothing said shown red. Bayt 5 and 6 share أن.
    @Test(arguments: [(5, 1), (5, 2), (5, 3), (8, 1), (8, 2), (10, 3)])
    func skipsOfSeveralBayts(from first: Int, count: Int) throws {
        let index = try Self.tuhfa()
        let t = tracker(index)
        let left = first...(first + count - 1)
        recite(Array(1..<first) + Array((first + count)...20), into: t, index)
        let red = Set(t.outcomes.filter { $0.value.isMistake }.keys)
        #expect(index.skippedBayts(t.outcomes) == Set(left), "skipped \(index.skippedBayts(t.outcomes).sorted()) \(words(of: left, index).map { "\($0)=\(t.outcomes[$0].map { "\($0)" } ?? "-")" })")
        #expect(red == Set(words(of: left, index)), "red bayts \(Set(red.map { index.refs[$0].bayt }).sorted())")
        #expect(index.mistakeCount(t.outcomes) == count)
        #expect(t.cursor == index.firstWordIndex(ofBayt: 21))
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

    // MARK: - The review

    @Test func aSkippedBaytIsOneReviewRow() throws {
        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == "tuhfa" })
        let index = RecitationIndex(matn: matn)
        let eight = words(of: 8...8, index).map { FlagKey(bayt: 8, half: index.refs[$0].half, wordIndex: index.refs[$0].wordIndex) }
        let one = FlagKey(bayt: 2, half: .sadr, wordIndex: 1)
        let items = ReviewItems.resolve(matn: matn, flags: Set(eight + [one]), skippedBayts: [8])
        #expect(items.map(\.location) == ["Bayt 2 · first half", "Bayt 8 · skipped"])
        #expect(Set(items[1].keys) == Set(eight))
        #expect(items[0].keys == [one])
        // After the sitting, the same flags are still one row.
        #expect(ReviewItems.resolve(matn: matn, flags: Set(eight)).map(\.location) == ["Bayt 8 · whole bayt"])
    }

    @Test func aHadithIsNeverGrouped() throws {
        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == "arbaeen" })
        let body = try #require(matn.hadiths.first { $0.number == 1 }).body
        let flags = Set(body.indices.map { FlagKey(bayt: 1, half: .sadr, wordIndex: $0) })
        #expect(ReviewItems.resolve(matn: matn, flags: flags).count == body.count)
    }

    @Test func theSittingCountsASkippedBaytOnce() {
        func m(_ id: Int, bayt: Int, added: Bool = false, fixed: Bool = false) -> ReviewSummary.Mistake {
            var x = ReviewSummary.Mistake(id: id, page: 1, bayt: bayt, half: .sadr, wordIndex: id,
                                          expected: "w", heard: added ? "x" : nil)
            x.added = added
            x.fixed = fixed
            return x
        }
        let summary = ReviewSummary(baytsRecited: 3, revealed: 0,
                                    mistakes: [m(0, bayt: 1), m(1, bayt: 2), m(2, bayt: 2), m(3, bayt: 2),
                                               m(4, bayt: 2, added: true), m(5, bayt: 3, fixed: true)],
                                    skippedBayts: [2])
        // Bayt 1's word, bayt 2 once, and the word added in it; not the fixed one.
        #expect(summary.mistakeCount == 3)
    }
}
