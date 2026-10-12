import Foundation
import SwiftUI

/// Owns a SpeechSource + RecitationTracker and publishes reveal state for the
/// reader. The tracker is pure; this class is the only place audio meets UI.
@MainActor
final class RecitationSession: ObservableObject {
    @Published private(set) var cursor: Int
    @Published private(set) var lockState: LockState = .idle
    /// Reveal state for the UI, cached and rebuilt only when the cursor advances
    /// (RevealState init is O(words); rebuilding per SwiftUI read would be wasteful).
    @Published private(set) var reveal: RevealState

    private let index: RecitationIndex
    private let tracker: RecitationTracker
    private let source: SpeechSource
    private var pump: Task<Void, Never>?
    private var startTime = Date()

    init(index: RecitationIndex, source: SpeechSource, startWordIndex: Int) {
        self.index = index
        self.source = source
        self.tracker = RecitationTracker(words: index.normalizedWords, startIndex: startWordIndex)
        self.cursor = startWordIndex
        self.reveal = RevealState(index: index, cursor: startWordIndex)
    }

    func start() {
        startTime = Date()
        pump = Task { await run() }
        Task { try? await source.start() }
    }

    func stop() {
        // Only stop the source. Its stream finishes once the engine finalises,
        // which lets the pump's `for await` loop end naturally — cancelling it
        // here would risk dropping the last recognised word.
        source.stop()
    }

    /// Drains the source stream into the tracker. Exposed for tests.
    func run() async {
        for await fragment in source.fragments {
            tracker.consume(fragment, at: Date().timeIntervalSince(startTime))
            lockState = tracker.lockState
            if tracker.cursor != cursor {       // rebuild reveal only on real progress
                cursor = tracker.cursor
                reveal = RevealState(index: index, cursor: cursor)
            }
        }
    }
}
