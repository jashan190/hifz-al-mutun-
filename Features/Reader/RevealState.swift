import Foundation

/// Answers "how many words of this hemistich are revealed?" from a global
/// cursor, using the flat index's back-references. Precomputes per-(bayt,half)
/// word ranges so lookups during rendering are O(1).
struct RevealState {
    private let cursor: Int
    private var startByHalf: [HalfKey: Int] = [:]
    private var countByHalf: [HalfKey: Int] = [:]

    private struct HalfKey: Hashable { let bayt: Int; let half: Half }

    init(index: RecitationIndex, cursor: Int) {
        self.cursor = cursor
        for (i, ref) in index.refs.enumerated() {
            let key = HalfKey(bayt: ref.bayt, half: ref.half)
            if startByHalf[key] == nil { startByHalf[key] = i }
            countByHalf[key, default: 0] += 1
        }
    }

    /// Number of words revealed in this hemistich (0 … its word count).
    func revealedWords(bayt: Int, half: Half) -> Int {
        let key = HalfKey(bayt: bayt, half: half)
        guard let start = startByHalf[key], let total = countByHalf[key] else { return 0 }
        return min(max(0, cursor - start), total)
    }
}
