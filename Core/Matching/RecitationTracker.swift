import Foundation

/// One recognized hint from a `SpeechSource`. `text` is the recognizer's latest
/// hypothesis for the audio since the last finalized result (raw,
/// un-normalized); `isFinal` marks that this audio range is now settled.
///
/// This mirrors `SpeechTranscriber`: each result covers its own audio range,
/// a volatile result is *replaced* by the next result for the same range, and a
/// final result is permanent. So the tracker keeps a committed state built from
/// final results only, and recomputes a tentative state on top of it for each
/// volatile result.
struct TranscriptFragment {
    let text: String
    let isFinal: Bool
}

enum LockState { case idle, locked, lost }

/// How a recited word was judged. Only finalized recognizer results produce an
/// outcome, so a mishearing in a volatile partial that is corrected before it
/// settles never shows as a mistake.
enum WordOutcome: Equatable {
    case correct
    /// Matched, but not exactly (a near miss) — shown amber, not flagged.
    case unsure
    /// Something else was said in this word's place.
    case wrong(heard: String)
    /// Passed over between two recited words.
    case skipped
    /// Jumped over while re-finding the place after the tracker was lost. The
    /// recognizer may simply have missed these, so they aren't called mistakes.
    case unheard

    var isMistake: Bool {
        switch self {
        case .wrong, .skipped: return true
        case .correct, .unsure, .unheard: return false
        }
    }
}

/// Every matching threshold in one place. These are provisional: they were
/// chosen against scripted tests, not yet tuned on real recitation on a device.
struct MatchTuning {
    /// Positions searched past the cursor while locked: the next word plus up
    /// to `lockedLookahead - 1` skipped words.
    var lockedLookahead = 4
    /// Positions searched while lost, to re-find the place.
    var lostWindow = 12
    /// Seconds without progress before a locked tracker counts as lost.
    var lostAfter: TimeInterval = 2.0
    /// Consecutive unmatched final tokens before a locked tracker counts as lost.
    var lostAfterUnmatched = 4
    /// Words shorter than this (e.g. و ف ب ل في من) must match exactly.
    var exactBelowLength = 3
    /// While lost, a single matching word re-locks only if it is at least this
    /// long; shorter words need the next word to match too.
    var resyncMinLength = 4

    /// Edit distance still accepted as the same word (shown as `.unsure`).
    func matchThreshold(_ a: String, _ b: String) -> Int {
        let n = min(a.count, b.count)
        return n < exactBelowLength ? 0 : max(1, n / 4)
    }

    /// A heard token this close to the expected word is probably a mishearing
    /// of it, so it is judged `.unsure` rather than `.wrong`.
    func nearMissThreshold(_ a: String, _ b: String) -> Int {
        max(2, min(a.count, b.count) / 2)
    }
}

/// Walks a cursor forward through a known word sequence on fuzzy matches of
/// recognizer hints, and judges each word it passes. Pure logic — no audio, no
/// UI, fully testable.
final class RecitationTracker {
    let words: [String]            // expected words, already normalized
    let tuning: MatchTuning

    /// Words revealed so far: [0, cursor). Follows volatile results too.
    var cursor: Int { current.cursor }
    var lockState: LockState { current.lock }
    /// Outcomes by flat word index, from finalized results only.
    var outcomes: [Int: WordOutcome] { committed.outcomes }

    private struct State {
        var cursor: Int
        var lock: LockState = .idle
        var outcomes: [Int: WordOutcome] = [:]
        /// Final tokens heard since the last match, as (raw, normalized).
        var pending: [(raw: String, norm: String)] = []
        var unmatchedRun = 0
        /// Lost only because of a pause (not because what was heard didn't fit):
        /// the place is still known, so nearby matches are judged as if locked.
        var lostBySilence = false
    }

    private var committed: State
    private var current: State
    private var lastProgress: TimeInterval = 0

    init(words: [String], startIndex: Int = 0, tuning: MatchTuning = MatchTuning()) {
        self.words = words
        self.tuning = tuning
        let start = Self.firstNonEmpty(from: min(max(0, startIndex), words.count), in: words)
        committed = State(cursor: start)
        current = committed
    }

    func reset(to index: Int) {
        committed = State(cursor: Self.firstNonEmpty(from: min(max(0, index), words.count), in: words))
        current = committed
        lastProgress = 0
    }

    func consume(_ fragment: TranscriptFragment, at time: TimeInterval) {
        // Split on whitespace FIRST, then normalize each token individually.
        // ArabicNormalize.normalize strips spaces, so normalizing the whole
        // string would collapse multi-word fragments into one run of letters.
        let tokens = fragment.text
            .split(whereSeparator: \.isWhitespace)
            .map { (raw: String($0), norm: ArabicNormalize.normalize(String($0))) }
            .filter { !$0.norm.isEmpty }

        // A volatile result replaces the previous one, so always build on the
        // committed state; a final result becomes the new committed state.
        var next = committed
        apply(tokens, to: &next)

        if next.cursor > current.cursor {
            lastProgress = time
        } else if fragment.isFinal, next.lock == .locked, time - lastProgress > tuning.lostAfter {
            // Only a final result can declare a pause: a volatile one is often
            // just the first fragment of the next utterance, and must never
            // change how later final results are judged. Only locked → lost;
            // never from idle (before the first match).
            next.lock = .lost
            next.lostBySilence = true
        }
        if fragment.isFinal { committed = next }
        current = next
    }

    // MARK: - Alignment

    private func apply(_ tokens: [(raw: String, norm: String)], to s: inout State) {
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let near = s.cursor..<min(words.count, s.cursor + tuning.lockedLookahead)
            let wide = s.cursor..<min(words.count, s.cursor + tuning.lostWindow)
            var found: (hit: Int, exact: Bool, uncertainGap: Bool)?
            if s.lock != .lost || s.lostBySilence, let (hit, exact) = match(token.norm, in: near) {
                // Before the first match (idle) a gap is as uncertain as a lost one.
                found = (hit, exact, s.lock == .idle)
            } else if s.lock == .lost, let (hit, exact) = match(token.norm, in: wide),
                      resyncAccepted(hit, tokens: tokens, at: i) {
                found = (hit, exact, true)
            }
            if let found {
                judgeGap(upTo: found.hit, in: &s, lost: found.uncertainGap)
                s.outcomes[found.hit] = found.exact ? .correct : .unsure
                s.cursor = Self.firstNonEmpty(from: found.hit + 1, in: words)
                s.lock = .locked
                s.lostBySilence = false
                s.pending = []
                s.unmatchedRun = 0
            } else if s.lock != .idle {
                s.pending.append(token)
                s.unmatchedRun += 1
                if s.unmatchedRun >= tuning.lostAfterUnmatched {
                    s.lock = .lost
                    s.lostBySilence = false
                    s.pending = []   // can't pair these with a slot once lost
                }
            }
            i += 1
        }
    }

    /// Judge the expected words passed over between the cursor and a match at
    /// `hit`. While the place is known, heard-but-unmatched tokens fill those
    /// slots in order (a substitution); slots left over were skipped. Words
    /// jumped while re-finding a lost place are `.unheard`.
    private func judgeGap(upTo hit: Int, in s: inout State, lost: Bool) {
        let gap = (s.cursor..<hit).filter { !words[$0].isEmpty }
        guard !gap.isEmpty else { return }   // tokens before an in-place match are extra words
        if lost {
            for w in gap { s.outcomes[w] = .unheard }
            return
        }
        for (k, w) in gap.enumerated() {
            guard k < s.pending.count else { s.outcomes[w] = .skipped; continue }
            // Any extra heard tokens beyond the gap belong to its last slot.
            let heard = k == gap.count - 1 ? s.pending[k...] : s.pending[k...k]
            let rawHeard = heard.map(\.raw).joined(separator: " ")
            let near = heard.contains {
                levenshtein($0.norm, words[w]) <= tuning.nearMissThreshold($0.norm, words[w])
            }
            s.outcomes[w] = near ? .unsure : .wrong(heard: rawHeard)
        }
    }

    /// While lost, accept a re-lock only on good evidence: a long word, or the
    /// next token matching the next word too. Short common words (في، من) would
    /// otherwise snap the cursor to the wrong place.
    private func resyncAccepted(_ hit: Int, tokens: [(raw: String, norm: String)], at i: Int) -> Bool {
        if words[hit].count >= tuning.resyncMinLength { return true }
        let after = Self.firstNonEmpty(from: hit + 1, in: words)
        guard i + 1 < tokens.count, after < words.count else { return false }
        return isMatch(tokens[i + 1].norm, words[after]) != nil
    }

    /// First position in `range` the token matches, and whether exactly.
    private func match(_ token: String, in range: Range<Int>) -> (Int, Bool)? {
        for i in range where !words[i].isEmpty {
            if let exact = isMatch(token, words[i]) { return (i, exact) }
        }
        return nil
    }

    /// nil if no match; true if exact, false if within the fuzzy threshold.
    private func isMatch(_ a: String, _ b: String) -> Bool? {
        if a == b { return true }
        return levenshtein(a, b) <= tuning.matchThreshold(a, b) ? false : nil
    }

    private static func firstNonEmpty(from i: Int, in words: [String]) -> Int {
        var i = i
        while i < words.count && words[i].isEmpty { i += 1 }
        return i
    }
}
