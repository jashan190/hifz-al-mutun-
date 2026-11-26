import Testing
import Foundation
@testable import HifzAlMutun

/// ﷺ is one word in the text and said as a phrase: any common salawat, or
/// its first words, is that word said right; leaving it out is a mistake.
@MainActor @Suite struct SalawatTests {
    /// Hadith 1 as the app tracks it, and the flat index of its first ﷺ.
    private static func hadith() throws -> (RecitationTracker, RecitationIndex, Int) {
        let store = ContentStore()
        store.load()
        let index = RecitationIndex(matn: try #require(store.matns.first { $0.id == "arbaeen" }))
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0, bayts: index.refs.map(\.bayt),
                                        idgham: index.idgham, prose: index.isProse)
        let salawat = try #require(index.displayWords.firstIndex { $0.hasPrefix("ﷺ") })
        return (tracker, index, salawat)
    }

    /// The hadith's words before ﷺ, then `said`, then the next four words.
    private func recite(_ said: String) throws -> (RecitationTracker, Int) {
        let (t, index, s) = try Self.hadith()
        let before = index.normalizedWords[..<s].joined(separator: " ")
        let after = index.normalizedWords[(s + 1)...(s + 4)].joined(separator: " ")
        t.consume(.init(text: "\(before) \(said) \(after)", isFinal: true), at: 0)
        #expect(t.cursor == s + 5, "\(said)")
        return (t, s)
    }

    @Test(arguments: ["صلى الله عليه وسلم", "صلى الله عليه وآله وسلم", "عليه الصلاة والسلام",
                      "صلى الله عليه", "صلى الله", "ﷺ"])
    func eachWayOfSayingItIsRight(_ said: String) throws {
        let (t, s) = try recite(said)
        #expect(t.outcomes[s] == .correct, "\(said): \(String(describing: t.outcomes[s]))")
        #expect(!t.outcomes.values.contains { $0.isMistake })
        #expect(t.added.isEmpty)
    }

    @Test func aPhraseSplitBetweenTwoResultsIsOneWord() throws {
        let (t, index, s) = try Self.hadith()
        t.consume(.init(text: index.normalizedWords[..<s].joined(separator: " ") + " صلى الله", isFinal: true), at: 0)
        t.consume(.init(text: "عليه وسلم " + index.normalizedWords[(s + 1)...(s + 4)].joined(separator: " "),
                        isFinal: true), at: 1)
        #expect(t.outcomes[s] == .correct)
        #expect(t.added.isEmpty)
        #expect(t.cursor == s + 5)
    }

    // Split anywhere: its first word ending one result, or its rest in two.
    @Test(arguments: [["صلى", "الله عليه وسلم"], ["صلى الله", "عليه", "وسلم"], ["صلى", "الله", "عليه وسلم"]])
    func aPhraseSplitAnywhereIsOneWord(_ parts: [String]) throws {
        let (t, index, s) = try Self.hadith()
        let before = index.normalizedWords[..<s].joined(separator: " ")
        let after = index.normalizedWords[(s + 1)...(s + 4)].joined(separator: " ")
        let results = ["\(before) \(parts[0])"] + parts.dropFirst().dropLast() + ["\(parts.last!) \(after)"]
        for (k, text) in results.enumerated() { t.consume(.init(text: text, isFinal: true), at: Double(k)) }
        #expect(t.outcomes[s] == .correct, "\(parts)")
        #expect(!t.outcomes.values.contains { $0.isMistake }, "\(parts)")
        #expect(t.added.isEmpty, "\(parts): \(t.added)")
        #expect(t.cursor == s + 5)
    }

    @Test func nothingIsTakenAfterAWholePhrase() throws {
        // صلى الله عليه وسلم said whole: a الله after it isn't more of it,
        // but what was said for the next word.
        let (t, index, s) = try Self.hadith()
        t.consume(.init(text: index.normalizedWords[..<s].joined(separator: " ") + " صلى الله عليه وسلم",
                        isFinal: true), at: 0)
        t.consume(.init(text: "الله", isFinal: true), at: 1)
        t.consume(.init(text: index.normalizedWords[(s + 2)...(s + 5)].joined(separator: " "), isFinal: true), at: 2)
        #expect(t.outcomes[s] == .correct)
        #expect(t.outcomes[s + 1] == .wrong(heard: "الله"), "\(String(describing: t.outcomes[s + 1]))")
    }

    @Test func leavingItOutIsAMistake() throws {
        let (t, s) = try recite("")
        #expect(t.outcomes[s] == .skipped)
    }

    @Test func aPoemsWordsAreLeftAlone() throws {
        // The Shatibiyya's وثنيت صلى الله ربي: no ﷺ in the text, so nothing
        // is joined, and each word is matched as written.
        let store = ContentStore()
        store.load()
        let index = RecitationIndex(matn: try #require(store.matns.first { $0.id == "shatibiyya" }))
        let t = RecitationTracker(words: index.normalizedWords, startIndex: 0, bayts: index.refs.map(\.bayt),
                                  idgham: index.idgham)
        let end = try #require(index.firstWordIndex(ofBayt: 3))
        t.consume(.init(text: index.normalizedWords[..<end].joined(separator: " "), isFinal: true), at: 0)
        #expect(t.cursor == end)
        #expect(!t.outcomes.values.contains { $0.isMistake })
    }
}
