import SwiftUI
import Combine

/// What a finished Review sitting covered, for the stop card.
struct ReviewSummary: Equatable {
    let baytsRecited: Int
    let mistakes: Int
    let revealed: Int
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

    private var session: RecitationSession?
    private var index: RecitationIndex?
    private var matnID: String?
    private var flags: FlagStore?
    private var applied: [Int: WordOutcome] = [:]   // outcomes already synced to flags
    private var cancellables: Set<AnyCancellable> = []

    var hasSession: Bool { session != nil }
    /// Listening (or getting ready to) with the microphone.
    var isLive: Bool {
        guard !isManual else { return false }
        switch status {
        case .preparing, .downloading, .listening: return true
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
        let session = RecitationSession(index: index, source: manual ? SilentSpeechSource() : makeSource(),
                                        startWordIndex: startIndex)
        if manual { session.stuckRevealAfter = nil }
        self.session = session

        cursor = session.cursor
        reveal = session.reveal
        session.$cursor.sink { [weak self] in self?.cursor = $0 }.store(in: &cancellables)
        session.$lockState.sink { [weak self] in self?.lockState = $0 }.store(in: &cancellables)
        session.$reveal.sink { [weak self] in self?.reveal = $0 }.store(in: &cancellables)
        session.$mistakeCount.sink { [weak self] in self?.mistakeCount = $0 }.store(in: &cancellables)
        session.$status.sink { [weak self] in self?.status = $0 }.store(in: &cancellables)
        session.$outcomes.sink { [weak self] in self?.syncFlags($0) }.store(in: &cancellables)

        session.start()
    }

    /// Stop listening but keep the results on screen (and let the recognizer's
    /// last, finalized result land) until the next session or `clear()`.
    func stop() {
        guard let session else { return }
        session.stop()
        let judged = session.outcomes
        if !judged.isEmpty, let index {
            summary = ReviewSummary(
                baytsRecited: Set(judged.keys.map { index.refs[$0].bayt }).count,
                mistakes: judged.values.filter(\.isMistake).count,
                revealed: judged.values.filter { $0 == .revealed }.count
            )
        }
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
    }

    // MARK: - During a sitting

    /// The reciter moved to another page by hand: continue from its top.
    func jump(toPage page: Int) {
        guard let index, let session else { return }
        session.jump(toWord: index.firstWordIndex(onPage: page))
    }

    /// The reciter tapped a bayt number: continue from that bayt.
    func jump(toBayt bayt: Int) {
        guard let index, let session, let w = index.firstWordIndex(ofBayt: bayt) else { return }
        session.jump(toWord: w)
    }

    /// Show the next word (a tap on the blank, or the manual sitting's only way on).
    func revealNext() { session?.revealNext() }

    /// "Not a mistake": voice recognition can be wrong.
    func dismissMistake(bayt: Int, half: Half, wordIndex: Int) {
        guard let session, let i = reveal?.flatIndex(bayt: bayt, half: half, wordIndex: wordIndex) else { return }
        session.dismissMistake(at: i)
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
            let error: SpeechSourceError = fail == "speech" ? .speechNotAuthorized
                : fail == "arabic" ? .localeUnsupported : .micNotAuthorized
            return MockSpeechSource(script: [], failure: error)
        }
        if let script = defaults.string(forKey: "debugRecite") {
            let pace = defaults.double(forKey: "debugReciteInterval")
            return MockSpeechSource(script: Self.parseDebugScript(script),
                                    interval: pace > 0 ? .milliseconds(Int(pace * 1000)) : nil)
        }
        #endif
        return AppleSpeechSource()
    }

    #if DEBUG
    /// Debug-only: launch with `-debugRecite "frag|frag|~frag"` to replay a
    /// scripted recitation instead of the microphone (the Simulator has no
    /// speech models). Fragments are separated by `|`; a leading `~` marks a
    /// volatile (not yet final) result. `-debugReciteInterval 0.8` paces them
    /// like live speech; `-debugVoiceFail mic|speech|arabic` simulates a
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
