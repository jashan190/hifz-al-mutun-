import Foundation

/// Where each hemistich's words sit in the flat recitation order. Built once per
/// session (it's O(words)) and shared by every `RevealState` snapshot.
struct RevealLayout {
    fileprivate struct HalfKey: Hashable { let bayt: Int; let half: Half }
    fileprivate var startByHalf: [HalfKey: Int] = [:]
    fileprivate var countByHalf: [HalfKey: Int] = [:]

    init(index: RecitationIndex) {
        for (i, ref) in index.refs.enumerated() {
            let key = HalfKey(bayt: ref.bayt, half: ref.half)
            if startByHalf[key] == nil { startByHalf[key] = i }
            countByHalf[key, default: 0] += 1
        }
    }
}

/// Answers "how many words of this hemistich are revealed, and how was each
/// one judged?" from a global cursor and the tracker's outcomes. Lookups during
/// rendering are O(1).
struct RevealState {
    private let layout: RevealLayout
    private let cursor: Int
    private let outcomes: [Int: WordOutcome]

    init(layout: RevealLayout, cursor: Int, outcomes: [Int: WordOutcome] = [:]) {
        self.layout = layout
        self.cursor = cursor
        self.outcomes = outcomes
    }

    init(index: RecitationIndex, cursor: Int, outcomes: [Int: WordOutcome] = [:]) {
        self.init(layout: RevealLayout(index: index), cursor: cursor, outcomes: outcomes)
    }

    /// Number of words revealed in this hemistich (0 … its word count).
    func revealedWords(bayt: Int, half: Half) -> Int {
        let key = RevealLayout.HalfKey(bayt: bayt, half: half)
        guard let start = layout.startByHalf[key], let total = layout.countByHalf[key] else { return 0 }
        return min(max(0, cursor - start), total)
    }

    /// How the word at `wordIndex` in this hemistich was judged, if it has been.
    func outcome(bayt: Int, half: Half, wordIndex: Int) -> WordOutcome? {
        let key = RevealLayout.HalfKey(bayt: bayt, half: half)
        guard let start = layout.startByHalf[key] else { return nil }
        return outcomes[start + wordIndex]
    }
}
