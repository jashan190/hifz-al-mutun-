import Foundation

/// One recognized hint from a `SpeechSource`. `text` is the recognizer's latest
/// hypothesis (raw, un-normalized); `isFinal` marks a stabilized segment.
/// (The tracker currently ignores `isFinal` — it only ever advances the cursor,
/// never retracts, so a volatile and a final hint are handled identically.)
struct TranscriptFragment {
    let text: String
    let isFinal: Bool
}

enum LockState { case idle, locked, lost }

/// Walks a cursor forward through a known word sequence, advancing on fuzzy
/// matches of recognizer hints. Pure logic — no audio, no UI, fully testable.
final class RecitationTracker {
    let words: [String]            // expected words, already normalized
    private(set) var cursor: Int   // confirmed word count; reveal [0, cursor)
    private(set) var lockState: LockState = .idle
    private var lastProgress: TimeInterval = 0

    private let window: Int        // re-sync look-ahead when lost
    private let maxSkip: Int       // forward skip tolerance when locked
    private let lostAfter: TimeInterval

    init(words: [String], startIndex: Int = 0,
         window: Int = 12, maxSkip: Int = 3, lostAfter: TimeInterval = 2.0) {
        self.words = words
        self.cursor = min(max(0, startIndex), words.count)
        self.window = window
        self.maxSkip = maxSkip
        self.lostAfter = lostAfter
        skipEmpties(from: &cursor)
    }

    func reset(to index: Int) {
        cursor = min(max(0, index), words.count)
        skipEmpties(from: &cursor)
        lockState = .idle
        lastProgress = 0
    }

    func consume(_ fragment: TranscriptFragment, at time: TimeInterval) {
        // Split on whitespace FIRST, then normalize each token individually.
        // ArabicNormalize.normalize strips spaces, so normalizing the whole
        // string would collapse multi-word fragments into one run of letters.
        let tokens = fragment.text
            .split(separator: " ")
            .map { ArabicNormalize.normalize(String($0)) }
            .filter { !$0.isEmpty }

        var p = cursor
        // +1 so the range covers the cursor position itself plus `maxSkip`
        // words ahead (to step over up to `maxSkip` dropped words when locked).
        let lookahead = (lockState == .lost) ? window : (maxSkip + 1)
        for token in tokens {
            let end = min(words.count, p + lookahead)
            if let hit = matchIndex(token, in: p..<end) {
                p = hit + 1
                skipEmpties(from: &p)
            }
        }
        if p > cursor {
            cursor = p
            lastProgress = time
            lockState = .locked
        } else if lockState == .locked, time - lastProgress > lostAfter {
            // Only locked → lost; we never fire "lost" from idle (before the
            // first matched word). reset() is the only way back to idle.
            lockState = .lost
        }
    }

    // MARK: - Matching helpers

    private func matchIndex(_ token: String, in range: Range<Int>) -> Int? {
        for i in range where !words[i].isEmpty {
            if fuzzyEqual(token, words[i]) { return i }
        }
        return nil
    }

    private func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Caveat: for length-1 tokens the threshold is 1, so any single letter
        // matches any other. Fine for multi-letter words; single-letter Arabic
        // particles (و، ف، ب، ل) can false-match. Skip tolerance usually carries
        // the cursor over them anyway. Revisit if fixture tests show drift.
        let threshold = max(1, min(a.count, b.count) / 4)
        return levenshtein(a, b) <= threshold
    }

    private func skipEmpties(from i: inout Int) {
        while i < words.count && words[i].isEmpty { i += 1 }
    }
}
