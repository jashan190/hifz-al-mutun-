import Foundation
import SwiftUI

/// Owns a SpeechSource + RecitationTracker and publishes reveal state for the
/// reader. The tracker is pure; this class is the only place audio meets UI.
@MainActor
final class RecitationSession: ObservableObject {
    @Published private(set) var cursor: Int
    @Published private(set) var lockState: LockState = .idle
    /// Reveal state for the UI, rebuilt only when the cursor or the judged
    /// outcomes change.
    @Published private(set) var reveal: RevealState
    /// Words judged wrong or skipped so far (finalized results only).
    @Published private(set) var mistakeCount = 0

    private let layout: RevealLayout
    private let tracker: RecitationTracker
    private let source: SpeechSource
    private var pump: Task<Void, Never>?
    private var startTime = Date()
    private var judged = 0   // outcomes.count when `reveal` was last built

    init(index: RecitationIndex, source: SpeechSource, startWordIndex: Int) {
        self.layout = RevealLayout(index: index)
        self.source = source
        self.tracker = RecitationTracker(words: index.normalizedWords, startIndex: startWordIndex)
        self.cursor = startWordIndex
        self.reveal = RevealState(layout: layout, cursor: startWordIndex)
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
            let outcomes = tracker.outcomes
            if tracker.cursor != cursor || outcomes.count != judged {
                cursor = tracker.cursor
                judged = outcomes.count
                reveal = RevealState(layout: layout, cursor: cursor, outcomes: outcomes)
                let mistakes = outcomes.values.filter(\.isMistake).count
                if mistakes != mistakeCount { mistakeCount = mistakes }
            }
        }
    }
}
