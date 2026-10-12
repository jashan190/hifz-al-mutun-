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

    private var session: RecitationSession?
    private var index: RecitationIndex?
    private var cancellables: Set<AnyCancellable> = []

    func start(matn: Matn, fromPage page: Int) {
        stop()   // clear any prior session first
        let index = RecitationIndex(matn: matn)
        self.index = index
        let source = AppleSpeechSource()
        let startIndex = index.firstWordIndex(onPage: page)
        let session = RecitationSession(index: index, source: source, startWordIndex: startIndex)
        self.session = session

        cursor = startIndex
        reveal = session.reveal
        session.$cursor.sink { [weak self] in self?.cursor = $0 }.store(in: &cancellables)
        session.$lockState.sink { [weak self] in self?.lockState = $0 }.store(in: &cancellables)
        session.$reveal.sink { [weak self] in self?.reveal = $0 }.store(in: &cancellables)

        session.start()
    }

    func stop() {
        session?.stop()
        session = nil
        index = nil
        cancellables.removeAll()
        lockState = .idle
        reveal = nil
    }

    /// The page the current reveal frontier sits on (for auto page-turn), or nil.
    func page(forCursor c: Int) -> Int? {
        guard let index, c > 0, c <= index.refs.count else { return nil }
        return index.refs[c - 1].page
    }
}
