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
/// one judged?". A word is revealed once judged, or while it sits in the
/// current run [anchor, cursor) — which follows volatile results ahead of the
/// judgments. Words never reached (e.g. pages jumped over) stay hidden.
struct RevealState {
    private let layout: RevealLayout
    private let anchor: Int
    private let cursor: Int
    private let outcomes: [Int: WordOutcome]

    init(layout: RevealLayout, anchor: Int = 0, cursor: Int, outcomes: [Int: WordOutcome] = [:]) {
        self.layout = layout
        self.anchor = anchor
        self.cursor = cursor
        self.outcomes = outcomes
    }

    init(index: RecitationIndex, anchor: Int = 0, cursor: Int, outcomes: [Int: WordOutcome] = [:]) {
        self.init(layout: RevealLayout(index: index), anchor: anchor, cursor: cursor, outcomes: outcomes)
    }

    private func isRevealed(_ i: Int) -> Bool {
        outcomes[i] != nil || (anchor <= i && i < cursor)
    }

    /// Number of words revealed from the start of this hemistich (0 … its
    /// word count). Runs start at hemistich boundaries, so this is a prefix.
    func revealedWords(bayt: Int, half: Half) -> Int {
        let key = RevealLayout.HalfKey(bayt: bayt, half: half)
        guard let start = layout.startByHalf[key], let total = layout.countByHalf[key] else { return 0 }
        var k = 0
        while k < total && isRevealed(start + k) { k += 1 }
        return k
    }

    /// Flat index of a hemistich's word, for acting on it (e.g. dismissing).
    func flatIndex(bayt: Int, half: Half, wordIndex: Int) -> Int? {
        layout.startByHalf[RevealLayout.HalfKey(bayt: bayt, half: half)].map { $0 + wordIndex }
    }

    /// How the word at `wordIndex` in this hemistich was judged, if it has been.
    func outcome(bayt: Int, half: Half, wordIndex: Int) -> WordOutcome? {
        let key = RevealLayout.HalfKey(bayt: bayt, half: half)
        guard let start = layout.startByHalf[key] else { return nil }
        return outcomes[start + wordIndex]
    }
}
