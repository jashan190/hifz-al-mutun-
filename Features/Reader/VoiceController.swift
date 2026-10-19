import SwiftUI
import Combine

/// What a finished Review sitting covered, for the stop card.
/// What a sitting (one press of the mic, until it stops) came to.
struct ReviewSummary: Equatable {
    let baytsRecited: Int
    let revealed: Int
    /// Each mistake, in recitation order.
    let mistakes: [Mistake]

    struct Mistake: Equatable, Identifiable {
        let id: Int              // flat word index
        let page: Int
        let bayt: Int
        let half: Half
        let expected: String     // the word as written
        /// What the recognizer heard in its place; nil when it was skipped.
        let heard: String?
        /// `heard` was said after `expected`, which the text doesn't have.
        var added = false
    }
}

/// Owns the live RecitationSession and mirrors its published state so PageScreen
/// (which observes THIS object) updates as words are recognised. The session's
/// start page isn't known until the user taps the mic, hence the lazy build.
/// Also keeps the saved flags in step with what the session judges.
@MainActor
final class VoiceController: ObservableObject {
    @Published private(set) var cursor = 0
    @Published private(set) var lockState: LockState = .idle
    @Published private(set) var reveal: RevealState?
    @Published private(set) var mistakeCount = 0
    @Published private(set) var status: VoiceStatus = .idle
    /// Set when a sitting ends, until the next one starts or it's dismissed.
    @Published var summary: ReviewSummary?
    /// True for a tap-to-reveal sitting without the microphone.
    @Published private(set) var isManual = false
    /// Why voice last failed to start, kept while a tap-to-reveal sitting
    /// carries on in its place (so the footer can still say why).
    @Published private(set) var voiceFailure: VoiceFailure?

    private var session: RecitationSession?
    private var index: RecitationIndex?
    private var matnID: String?
    private var flags: FlagStore?
    private var applied: [Int: WordOutcome] = [:]   // outcomes already synced to flags
    private var cancellables: Set<AnyCancellable> = []

    var hasSession: Bool { session != nil }

    /// A sitting is running (by voice or by tap), as opposed to stopped with
    /// its results still on screen.
    var isActive: Bool {
        guard session != nil else { return false }
        switch status {
        case .preparing, .downloading, .loadingModel, .listening: return true
        case .idle, .failed: return false
        }
    }
    /// Listening (or getting ready to) with the microphone.
    var isLive: Bool {
        guard !isManual else { return false }
        switch status {
        case .preparing, .downloading, .loadingModel, .listening: return true
        case .idle, .failed: return false
        }
    }

    /// Start listening from the top of `page` (or from a bayt).
    func start(matn: Matn, fromPage page: Int, bayt: Int? = nil, flags: FlagStore?, manual: Bool = false) {
        clear()   // drop any prior session and its results first
        let index = RecitationIndex(matn: matn)
        self.index = index
        self.matnID = matn.id
        self.flags = flags
        self.isManual = manual
        let startIndex = bayt.flatMap { index.firstWordIndex(ofBayt: $0) } ?? index.firstWordIndex(onPage: page)
        let source = manual ? SilentSpeechSource() : makeSource()
        let session = RecitationSession(index: index, source: source, startWordIndex: startIndex)
        if let whisper = source as? WhisperSpeechSource, VowelChecker.modelURL != nil,
           let phonemes = PhonemeIndex(matnID: matn.id, index: index) {
            whisper.keepsAudio = true
            // The session starts now; finals heard while the model loads wait for it.
            Task { [weak session, weak whisper] in
                guard let model = await VowelChecker.sharedModel() else {
                    whisper?.keepsAudio = false   // no model: stop keeping audio for it
                    return
                }
                session?.vowels = VowelChecker(model: model, phonemes: phonemes, written: index.displayWords)
            }
        }
        if manual {
            session.revealOutcome = .shown   // reviewing by tap: reveals aren't flagged
        }
        self.session = session

        cursor = session.cursor
        reveal = session.reveal
        session.$cursor.sink { [weak self] in self?.cursor = $0 }.store(in: &cancellables)
        session.$lockState.sink { [weak self] in self?.lockState = $0 }.store(in: &cancellables)
        session.$reveal.sink { [weak self] in self?.reveal = $0 }.store(in: &cancellables)
        session.$mistakeCount.sink { [weak self] in self?.mistakeCount = $0 }.store(in: &cancellables)
        session.$status.sink { [weak self] in self?.status = $0 }.store(in: &cancellables)
        session.$outcomes.sink { [weak self] outcomes in
            self?.syncFlags(outcomes)
            // The recognizer's last result can land after the stop.
            if self?.summary != nil { self?.summary = self?.makeSummary(outcomes, added: session.added) }
        }.store(in: &cancellables)
        session.$added.sink { [weak self] added in
            if self?.summary != nil { self?.summary = self?.makeSummary(session.outcomes, added: added) }
        }.store(in: &cancellables)
        session.$status.sink { [weak self] status in
            if case .failed(let why) = status { self?.voiceFailure = why }
        }.store(in: &cancellables)

        session.start()
    }

    /// Stop listening but keep the results on screen (and let the recognizer's
    /// last, finalized result land) until the next session or `clear()`.
    func stop() {
        guard let session else { return }
        session.stop()
        summary = makeSummary(session.outcomes, added: session.added)
    }

    private func makeSummary(_ judged: [Int: WordOutcome], added: [Int: String]) -> ReviewSummary? {
        // A sitting can end with only added words (from the guess) to show.
        guard let index, !judged.isEmpty || !added.isEmpty else { return nil }
        var mistakes = judged.filter(\.value.isMistake).keys.map { i -> ReviewSummary.Mistake in
            let ref = index.refs[i]
            var heard: String?
            if case .wrong(let said) = judged[i] { heard = said }
            return .init(id: i, page: ref.page, bayt: ref.bayt, half: ref.half,
                         expected: index.displayWords[i], heard: heard)
        }
        // Added words follow the word they came after (ids past every word's).
        mistakes += added.map { i, words in
            let ref = index.refs[i]
            return .init(id: index.refs.count + i, page: ref.page, bayt: ref.bayt, half: ref.half,
                         expected: index.displayWords[i], heard: words, added: true)
        }
        let n = index.refs.count
        mistakes.sort { ($0.id % n, $0.added ? 1 : 0) < ($1.id % n, $1.added ? 1 : 0) }
        return ReviewSummary(
            baytsRecited: Set(judged.keys.map { index.refs[$0].bayt }).count,
            revealed: judged.values.filter { $0 == .revealed }.count,
            mistakes: mistakes
        )
    }

    /// Voice couldn't start: carry on as a tap-to-reveal sitting from the same
    /// place, keeping the reason for the footer.
    func fallBackToManual(matn: Matn, page: Int) {
        let why = voiceFailure
        start(matn: matn, fromPage: page, flags: flags, manual: true)
        voiceFailure = why
    }

    /// Drop the session and everything it revealed.
    func clear() {
        session?.stop()
        session = nil
        index = nil
        applied = [:]
        cancellables.removeAll()
        lockState = .idle
        reveal = nil
        mistakeCount = 0
        status = .idle
        summary = nil
        isManual = false
        voiceFailure = nil
    }

    // MARK: - During a sitting

    /// The reciter moved to another page by hand: continue from its top.
    func jump(toPage page: Int) {
        guard isActive, let index, let session else { return }
        session.jump(toWord: index.firstWordIndex(onPage: page))
    }

    /// The reciter tapped a bayt number: continue from that bayt.
    func jump(toBayt bayt: Int) {
        guard isActive, let index, let session, let w = index.firstWordIndex(ofBayt: bayt) else { return }
        session.jump(toWord: w)
    }

    /// Show the next word (a tap on the blank, or the manual sitting's only way on).
    func revealNext() {
        guard isActive else { return }
        session?.revealNext()
    }

    /// "Not a mistake": voice recognition can be wrong.
    func dismissMistake(bayt: Int, half: Half, wordIndex: Int) {
        guard let session, let i = reveal?.flatIndex(bayt: bayt, half: half, wordIndex: wordIndex) else { return }
        session.dismissMistake(at: i)
    }

    /// The same for words shown added after a word.
    func dismissAdded(bayt: Int, half: Half, wordIndex: Int) {
        guard let session, let i = reveal?.flatIndex(bayt: bayt, half: half, wordIndex: wordIndex) else { return }
        session.dismissAdded(after: i)
    }

    /// The page to show for the cursor (auto page-turn): the page of the next
    /// word expected, so the page turns as soon as the last word of a page is
    /// recited; at the very end, the last page.
    func page(forCursor c: Int) -> Int? {
        guard let index, !index.refs.isEmpty else { return nil }
        return index.refs[min(max(0, c), index.refs.count - 1)].page
    }

    // MARK: - Flags

    /// Mistakes and revealed words gain a flag; a flagged word recited
    /// correctly (or dismissed as "Not a mistake") loses it.
    private func syncFlags(_ outcomes: [Int: WordOutcome]) {
        guard let flags, let index, let matnID else { return }
        for (i, outcome) in outcomes where applied[i] != outcome {
            let ref = index.refs[i]
            let key = FlagKey(bayt: ref.bayt, half: ref.half, wordIndex: ref.wordIndex)
            if outcome.flagsWord {
                flags.setFlag(true, matnID: matnID, key)
            } else if outcome == .correct {
                flags.setFlag(false, matnID: matnID, key)
            }
        }
        applied = outcomes
    }

    // MARK: - Sources

    private func makeSource() -> SpeechSource {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let fail = defaults.string(forKey: "debugVoiceFail") {
            let error: SpeechSourceError = fail == "download" ? .modelDownloadFailed : .micNotAuthorized
            return MockSpeechSource(script: [], failure: error)
        }
        if let script = defaults.string(forKey: "debugRecite") {
            let pace = defaults.double(forKey: "debugReciteInterval")
            return MockSpeechSource(script: Self.parseDebugScript(script),
                                    interval: pace > 0 ? .milliseconds(Int(pace * 1000)) : nil)
        }
        #endif
        return WhisperSpeechSource()
    }

    #if DEBUG
    /// Debug-only: launch with `-debugRecite "frag|frag|~frag"` to replay a
    /// scripted recitation instead of the microphone. Fragments are separated by `|`; a leading `~` marks a
    /// volatile (not yet final) result. `-debugReciteInterval 0.8` paces them
    /// like live speech; `-debugVoiceFail mic|download` simulates a
    /// failure to start.
    static func parseDebugScript(_ script: String) -> [TranscriptFragment] {
        script.split(separator: "|").map { raw in
            let volatile = raw.hasPrefix("~")
            return TranscriptFragment(text: String(volatile ? raw.dropFirst() : raw),
                                      isFinal: !volatile)
        }
    }
    #endif
}
