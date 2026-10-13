import SwiftUI
import Combine

/// Owns the live RecitationSession and mirrors its published state so PageScreen
/// (which observes THIS object) updates as words are recognised. The session's
/// start page isn't known until the user taps the mic, hence the lazy build.
@MainActor
final class VoiceController: ObservableObject {
    @Published private(set) var cursor = 0
    @Published private(set) var lockState: LockState = .idle
    @Published private(set) var reveal: RevealState?
    @Published private(set) var mistakeCount = 0

    private var session: RecitationSession?
    private var index: RecitationIndex?
    private var cancellables: Set<AnyCancellable> = []

    func start(matn: Matn, fromPage page: Int) {
        clear()   // drop any prior session and its results first
        let index = RecitationIndex(matn: matn)
        self.index = index
        let source = makeSource()
        let startIndex = index.firstWordIndex(onPage: page)
        let session = RecitationSession(index: index, source: source, startWordIndex: startIndex)
        self.session = session

        cursor = startIndex
        reveal = session.reveal
        session.$cursor.sink { [weak self] in self?.cursor = $0 }.store(in: &cancellables)
        session.$lockState.sink { [weak self] in self?.lockState = $0 }.store(in: &cancellables)
        session.$reveal.sink { [weak self] in self?.reveal = $0 }.store(in: &cancellables)
        session.$mistakeCount.sink { [weak self] in self?.mistakeCount = $0 }.store(in: &cancellables)

        session.start()
    }

    /// Stop listening but keep the results on screen (and let the recognizer's
    /// last, finalized result land) until the next session or `clear()`.
    func stop() {
        session?.stop()
    }

    /// Drop the session and everything it revealed.
    func clear() {
        session?.stop()
        session = nil
        index = nil
        cancellables.removeAll()
        lockState = .idle
        reveal = nil
        mistakeCount = 0
    }

    private func makeSource() -> SpeechSource {
        #if DEBUG
        if let script = UserDefaults.standard.string(forKey: "debugRecite") {
            return MockSpeechSource(script: Self.parseDebugScript(script))
        }
        #endif
        return AppleSpeechSource()
    }

    #if DEBUG
    /// Debug-only: launch with `-debugRecite "frag|frag|~frag"` to replay a
    /// scripted recitation instead of the microphone (the Simulator has no
    /// speech models). Fragments are separated by `|`; a leading `~` marks a
    /// volatile (not yet final) result.
    static func parseDebugScript(_ script: String) -> [TranscriptFragment] {
        script.split(separator: "|").map { raw in
            let volatile = raw.hasPrefix("~")
            return TranscriptFragment(text: String(volatile ? raw.dropFirst() : raw),
                                      isFinal: !volatile)
        }
    }
    #endif

    /// The page the current reveal frontier sits on (for auto page-turn), or nil.
    func page(forCursor c: Int) -> Int? {
        guard let index, c > 0, c <= index.refs.count else { return nil }
        return index.refs[c - 1].page
    }
}
