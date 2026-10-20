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
struct TranscriptFragment: Equatable {
    let text: String
    let isFinal: Bool
    /// A final result's audio (16 kHz mono), when the source keeps it, for
    /// checking the harakat of the words it settles.
    var audio: [Float]? = nil
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
    /// Shown as help when the reciter was stuck (a tap, or a long pause).
    case revealed
    /// Shown by tap in a sitting without voice: nothing was recited to judge.
    case shown

    /// A recitation mistake: shown in red, with a haptic.
    var isMistake: Bool {
        switch self {
        case .wrong, .skipped: return true
        case .correct, .unsure, .unheard, .revealed, .shown: return false
        }
    }

    /// Marks the word for review later (UX.md "flags"): mistakes, and words
    /// the reciter needed revealed.
    var flagsWord: Bool { isMistake || self == .revealed }
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

    /// The next word expected; recited words are [anchor, cursor). Follows
    /// volatile results too.
    var cursor: Int { current.cursor }
    /// Where the current run began (the session start, or the last jump).
    var anchor: Int { committed.anchor }
    var lockState: LockState { current.lock }
    /// Outcomes by flat word index, from finalized results only. These are
    /// kept: flags and the summary come from them.
    var outcomes: [Int: WordOutcome] { applyingOverrides(committed.outcomes) }
    /// What to show now: the finalized outcomes, plus settled judgments from
    /// the recognizer's current guess (see `updateTentative`). A mistake
    /// shows within an update of the next words being heard, instead of
    /// waiting for the recognizer to finalize the passage.
    var shownOutcomes: [Int: WordOutcome] {
        applyingOverrides(committed.outcomes.merging(stable) { kept, _ in kept })
    }
    /// What was heard for each word judged amber or red, raw, so the letters
    /// that differ can be shown.
    var heard: [Int: String] {
        let shown = shownOutcomes
        return current.heard.merging(tentativeHeard) { kept, _ in kept }
            .merging(vowelSlips) { _, slip in slip }.filter {
            switch shown[$0.key] {
            case .unsure?, .wrong?: return true
            default: return false
            }
        }
    }

    private struct State {
        var cursor: Int
        var anchor: Int
        var lock: LockState = .idle
        var outcomes: [Int: WordOutcome] = [:]
        /// What was heard for an inexact match or a wrong word (raw).
        var heard: [Int: String] = [:]
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
    /// Judgments from the current guess, beyond the finalized ones: the last
    /// update's, and those the last two updates agreed on.
    private var tentative: [Int: WordOutcome] = [:]
    private var stable: [Int: WordOutcome] = [:]
    /// What was heard for the word being recited, judged before it is done.
    private var tentativeHeard: [Int: String] = [:]
    /// The reciter's corrections ("Not a mistake"), kept over later judgments
    /// of the same word (a shown guess that is then finalized).
    private var overrides: [Int: WordOutcome] = [:]

    /// Words heard right but with a vowel slip (the vowel check), as said.
    private var vowelSlips: [Int: String] = [:]

    private func applyingOverrides(_ judged: [Int: WordOutcome]) -> [Int: WordOutcome] {
        var judged = judged
        for (i, said) in vowelSlips where judged[i] == .correct { judged[i] = .wrong(heard: said) }
        for (i, o) in overrides where judged[i] != nil { judged[i] = o }
        return judged
    }

    init(words: [String], startIndex: Int = 0, tuning: MatchTuning = MatchTuning()) {
        self.words = words
        self.tuning = tuning
        let start = Self.firstNonEmpty(from: min(max(0, startIndex), words.count), in: words)
        committed = State(cursor: start, anchor: start)
        current = committed
    }

    /// Continue from `index` (a page or bayt the reciter moved to). Earlier
    /// judgments are kept; anything from `index` on is forgotten, so jumping
    /// back to recite a passage again starts it fresh.
    func jump(to index: Int, at time: TimeInterval) {
        let start = Self.firstNonEmpty(from: min(max(0, index), words.count), in: words)
        var s = State(cursor: start, anchor: start)
        s.outcomes = outcomes.filter { $0.key < start }
        s.heard = committed.heard.filter { $0.key < start }
        overrides = overrides.filter { $0.key < start }
        vowelSlips = vowelSlips.filter { $0.key < start }
        generation += 1
        committed = s
        current = s
        clearTentative()
        lastProgress = time
    }

    /// Replace a word's judgment (e.g. the reciter says "Not a mistake").
    func override(_ index: Int, with outcome: WordOutcome) {
        guard shownOutcomes[index] != nil else { return }
        overrides[index] = outcome
    }

    /// Bumped by each `jump(to:)`, so a vowel check begun before it (on the
    /// earlier recitation of a word) is ignored.
    private(set) var generation = 0

    /// The vowel check heard a word Whisper placed as correct with a short
    /// vowel changed: it becomes a mistake, shown as `said` (the written word
    /// with that vowel). Ignored unless the word is still judged correct, and
    /// the check began after the last jump (`generation`).
    func markVowelSlip(_ index: Int, said: String, generation: Int) {
        guard generation == self.generation, committed.outcomes[index] == .correct else { return }
        vowelSlips[index] = said
    }

    /// Show the next expected word, and move past it: as help (`.revealed`,
    /// flagged) while reciting, or plainly (`.shown`) when reviewing by tap.
    func revealNext(at time: TimeInterval, as outcome: WordOutcome = .revealed) {
        let i = committed.cursor
        guard i < words.count else { return }
        overrides[i] = nil
        vowelSlips[i] = nil
        committed.outcomes[i] = outcome
        committed.heard[i] = nil
        committed.cursor = Self.firstNonEmpty(from: i + 1, in: words)
        committed.lock = .locked           // the place is known again
        committed.lostBySilence = false
        committed.pending = []
        committed.unmatchedRun = 0
        current = committed                // any volatile guess is superseded
        clearTentative()
        lastProgress = time
    }

    /// Seconds since the cursor last moved.
    func silence(at time: TimeInterval) -> TimeInterval { time - lastProgress }

    /// Restart the silence clock (e.g. once the microphone is actually live).
    func restartClock(at time: TimeInterval) { lastProgress = time }

    /// Called on a timer: during a long pause no result arrives at all, so show
    /// the "lost" cue from here. Display only — it never changes how the next
    /// final result is judged.
    func noteSilence(at time: TimeInterval) {
        if current.lock == .locked, time - lastProgress > tuning.lostAfter {
            current.lock = .lost
        }
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
        updateTentative()
    }

    /// A judgment from the guess is shown once it is settled: the last two
    /// updates agree on it, or a word recited exactly already follows it in
    /// this guess (the recognizer revises mostly its last word) — for a
    /// skip, only when the word before it was heard exactly too. The word
    /// still being recited is judged too, letter by letter (`inProgress`), so
    /// a wrong word shows without waiting for the next one.
    private func updateTentative() {
        // The guess only judges words from the committed cursor on.
        var latest = current.outcomes.filter { $0.key >= committed.cursor && committed.outcomes[$0.key] == nil }
        tentativeHeard = [:]
        if let (i, outcome, heard) = inProgress() {
            latest[i] = outcome
            tentativeHeard[i] = heard
        }
        stable = latest.filter { judged in
            if tentative[judged.key] == judged.value { return true }
            // A word heard only nearly may have swallowed the next one
            // (وأغنى غناء heard as وأغناء): a skip after it waits to agree.
            if judged.value == .skipped,
               let before = (committed.anchor..<judged.key).last(where: { !words[$0].isEmpty }),
               current.outcomes[before] != .correct { return false }
            let next = Self.firstNonEmpty(from: judged.key + 1, in: words)
            return next < current.cursor && current.outcomes[next] == .correct
                && words[next].count >= tuning.exactBelowLength
        }
        tentative = latest
    }

    /// The word at the cursor, judged from what the guess holds after the
    /// last matched word. Its letters are compared with the word's own as far
    /// as they go: while they agree (allowing a misheard letter) the word is
    /// still being said; once they part, it is wrong. A lone letter, easily
    /// dropped by the recognizer, isn't judged this way. The previous word
    /// said again (going back over it) isn't this word said wrong.
    private func inProgress() -> (Int, WordOutcome, String)? {
        let i = current.cursor
        guard current.lock == .locked, i < words.count, words[i].count > 1 else { return nil }
        var pending = current.pending[...]
        if let before = (current.anchor..<i).last(where: { !words[$0].isEmpty }) {
            while let token = pending.first, isMatch(token.norm, words[before]) != nil { pending.removeFirst() }
        }
        guard let first = pending.first else { return nil }
        let raw = pending.map(\.raw).joined(separator: " ")
        let said = pending.map(\.norm).joined()
        let word = words[i]
        if said.count < word.count {
            // Still being said: the letters so far, against the word's start.
            let closest = ((said.count - 1)...(said.count + 1)).filter { $0 > 0 && $0 <= word.count }
                .map { levenshtein(said, String(word.prefix($0))) }.min() ?? said.count
            if closest <= max(1, said.count / 4) { return nil }
        }
        let near = levenshtein(first.norm, word) <= tuning.nearMissThreshold(first.norm, word)
        return (i, near ? .unsure : .wrong(heard: raw), raw)
    }

    private func clearTentative() {
        tentative = [:]
        stable = [:]
        tentativeHeard = [:]
    }

    // MARK: - Alignment

    private func apply(_ tokens: [(raw: String, norm: String)], to s: inout State) {
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let near = s.cursor..<min(words.count, s.cursor + tuning.lockedLookahead)
            let wide = s.cursor..<min(words.count, s.cursor + tuning.lostWindow)
            var found: (hit: Int, exact: Bool, uncertainGap: Bool, heard: String)?
            // Words the token covers before `hit` (a prefix written apart, e.g.
            // بِـ: بِسْمِ heard as ببسم): judged with it, not as a gap.
            var joinedFrom: Int?
            let placeKnown = s.lock != .lost || s.lostBySilence
            if placeKnown, let joined = matchJoined(token.norm, in: near),
               joined.exact || !(match(token.norm, in: near)?.1 ?? false) {
                found = (joined.end, joined.exact, false, token.raw)
                joinedFrom = s.cursor
            } else if placeKnown, let (hit, exact) = match(token.norm, in: near, filling: s.pending.count) {
                // Before the first match (idle) a gap is as uncertain as a lost one.
                found = (hit, exact, s.lock == .idle, token.raw)
            } else if placeKnown, s.lock != .idle, let last = s.pending.last,
                      let (hit, exact) = match(last.norm + token.norm, in: near) {
                // One word heard as two (كالأترج heard as كل ترجح): the last
                // unmatched token and this one together.
                s.pending.removeLast()
                found = (hit, exact, false, last.raw + token.raw)
            } else if s.lock == .lost, let (hit, exact) = match(token.norm, in: wide),
                      resyncAccepted(hit, tokens: tokens, at: i) {
                found = (hit, exact, true, token.raw)
            }
            if let found {
                if let from = joinedFrom {
                    for w in from..<found.hit where !words[w].isEmpty {
                        s.outcomes[w] = found.exact ? .correct : .unsure
                        s.heard[w] = nil
                    }
                } else {
                    judgeGap(upTo: found.hit, in: &s, lost: found.uncertainGap)
                }
                s.outcomes[found.hit] = found.exact ? .correct : .unsure
                s.heard[found.hit] = found.exact || joinedFrom != nil ? nil : found.heard
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
            for w in gap { s.outcomes[w] = .unheard; s.heard[w] = nil }
            return
        }
        for (k, w) in gap.enumerated() {
            guard k < s.pending.count else {
                // A lone letter (a prefix written apart) is hard to hear and
                // easily dropped by the recognizer: check it, don't call it wrong.
                s.outcomes[w] = words[w].count == 1 ? .unsure : .skipped
                s.heard[w] = nil
                continue
            }
            // Any extra heard tokens beyond the gap belong to its last slot.
            let heard = k == gap.count - 1 ? s.pending[k...] : s.pending[k...k]
            let rawHeard = heard.map(\.raw).joined(separator: " ")
            let near = heard.contains {
                levenshtein($0.norm, words[w]) <= tuning.nearMissThreshold($0.norm, words[w])
            }
            s.outcomes[w] = near ? .unsure : .wrong(heard: rawHeard)
            s.heard[w] = rawHeard
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

    /// The token heard as several expected words run together, starting at
    /// `start`: the last word it covers, and whether exactly. Only runs whose
    /// words before the last are short (a prefix or particle written apart),
    /// so a long skipped word is never absorbed.
    private func matchJoined(_ token: String, in range: Range<Int>) -> (end: Int, exact: Bool)? {
        var joined = ""
        var count = 0
        var lastLength = 0
        for i in range where !words[i].isEmpty {
            if count > 0, lastLength > 2 { return nil }   // previous piece too long to be a prefix
            joined += words[i]
            lastLength = words[i].count
            count += 1
            if count >= 2, let exact = isMatch(token, joined) { return (i, exact) }
        }
        return nil
    }

    /// First position in `range` the token matches, and whether exactly.
    private func match(_ token: String, in range: Range<Int>) -> (Int, Bool)? {
        for i in range where !words[i].isEmpty {
            if let exact = isMatch(token, words[i]) { return (i, exact) }
        }
        return nil
    }

    /// As `match`, but an exact match further on wins over a near one when
    /// the `unmatched` tokens heard before it can fill the words between
    /// (من إذا heard for أمّا إذا: إذا is إذا, not a near أمّا).
    private func match(_ token: String, in range: Range<Int>, filling unmatched: Int) -> (Int, Bool)? {
        guard let first = match(token, in: range), !first.1 else { return match(token, in: range) }
        var between = 0
        for i in range where !words[i].isEmpty {
            if i > first.0, token == words[i] { return (i, true) }
            between += 1
            if between > unmatched { break }
        }
        return first
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
