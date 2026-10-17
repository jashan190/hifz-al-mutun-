import Foundation
import SwiftUI

/// Where voice review is, for the mic button and footer.
enum VoiceStatus: Equatable {
    case idle
    case preparing                 // asking permission, loading the model
    case downloading(Double)       // fetching the speech model, 0…1
    case loadingModel              // loading it (compiling it, the first time)
    case listening
    case failed(VoiceFailure)
}

/// Why voice review couldn't start, phrased for what the reciter can do.
enum VoiceFailure: Equatable {
    case micDenied                 // → Open Settings
    case downloadFailed            // no internet for the first download
    case other(String)

    init(_ error: Error) {
        switch error as? SpeechSourceError {
        case .micNotAuthorized?: self = .micDenied
        case .modelDownloadFailed?: self = .downloadFailed
        case nil: self = .other(error.localizedDescription)
        }
    }
}

/// Owns a SpeechSource + RecitationTracker and publishes reveal state for the
/// reader. The tracker is pure; this class is the only place audio meets UI.
@MainActor
final class RecitationSession: ObservableObject {
    @Published private(set) var cursor: Int
    @Published private(set) var lockState: LockState = .idle
    @Published private(set) var status: VoiceStatus = .idle
    /// Reveal state for the UI, rebuilt only when the cursor or the judged
    /// outcomes change.
    @Published private(set) var reveal: RevealState
    /// Words shown wrong or skipped so far (for the haptic). Includes
    /// judgments from the recognizer's guess that aren't finalized yet.
    @Published private(set) var mistakeCount = 0
    /// Every finalized judgment, by flat index (for flags and the summary).
    @Published private(set) var outcomes: [Int: WordOutcome] = [:]

    /// Reveal the next word after this long without progress (UX.md: "about 8
    /// seconds"). nil turns it off (tap-to-reveal only).
    var stuckRevealAfter: TimeInterval? = 8

    private let layout: RevealLayout
    private let tracker: RecitationTracker
    private let source: SpeechSource
    private var pump: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var startTime = Date()
    private var anchor: Int
    private var shown: [Int: WordOutcome] = [:]
    private var heard: [Int: String] = [:]
    /// Set by stop(): late events from the source (a download still finishing,
    /// a "listening" that crossed paths with the stop) must not revive it.
    private var stopped = false
    /// How a reveal is recorded: as help (flagged) when reciting by voice,
    /// or plainly shown in a tap-to-reveal sitting.
    var revealOutcome: WordOutcome = .revealed
    /// Checks the harakat of words as they settle, when the phoneme model is
    /// available; the source must then attach audio to its finals.
    var vowels: VowelChecker?

    init(index: RecitationIndex, source: SpeechSource, startWordIndex: Int) {
        let layout = RevealLayout(index: index)
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: startWordIndex)
        self.layout = layout
        self.source = source
        self.tracker = tracker
        self.cursor = tracker.cursor
        self.anchor = tracker.anchor
        self.reveal = RevealState(layout: layout, anchor: tracker.anchor, cursor: tracker.cursor)
    }

    private var now: TimeInterval { Date().timeIntervalSince(startTime) }

    func start() {
        stopped = false
        startTime = Date()
        status = .preparing
        source.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        pump = Task { await run() }
        // Keep the handle: stop() must be able to cancel a start that is still
        // waiting on permission or a model download.
        startTask = Task { [weak self, source] in
            do {
                try await source.start()
            } catch is CancellationError {
            } catch {
                self?.fail(error)
            }
        }
    }

    func stop() {
        stopped = true
        startTask?.cancel()
        clock?.cancel()
        // Stop the source. Its stream finishes once the engine finalises, which
        // lets the pump's `for await` loop end naturally — cancelling the pump
        // here would risk dropping the last recognised word.
        source.stop()
        if case .failed = status { return }
        status = .idle
    }

    /// Continue from another word (a page swiped to, or a bayt tapped).
    func jump(toWord index: Int) {
        tracker.jump(to: index, at: now)
        publish()
    }

    /// The reciter says a red word was right after all (voice recognition can
    /// be wrong).
    func dismissMistake(at index: Int) {
        tracker.override(index, with: .correct)
        publish()
    }

    /// Show the next word as help (a tap on the blank, or a long pause).
    func revealNext() {
        guard !stopped else { return }
        tracker.revealNext(at: now, as: revealOutcome)
        publish()
    }

    /// Drains the source stream into the tracker. Exposed for tests.
    func run() async {
        for await fragment in source.fragments {
            let before = tracker.outcomes
            tracker.consume(fragment, at: now)
            publish()
            if let vowels, fragment.isFinal, let audio = fragment.audio {
                checkVowels(settled: tracker.outcomes.filter { before[$0.key] == nil }, audio: audio, with: vowels)
            }
        }
    }

    /// Checks the words a final result settled against its audio: those
    /// heard right, and near misses (said, though Whisper spelled them
    /// differently; only a word judged correct can become a slip). Skipped
    /// words aren't in the audio and are left out. Not when a word was wrong
    /// or unheard: its audio doesn't hold its phonemes, and would throw the
    /// alignment off.
    private func checkVowels(settled: [Int: WordOutcome], audio: [Float], with vowels: VowelChecker) {
        guard settled.values.allSatisfy({ $0 == .correct || $0 == .unsure || $0 == .skipped }) else { return }
        let said = settled.filter { $0.value != .skipped }.keys.sorted()
        guard !said.isEmpty else { return }
        Task {
            let slips = await vowels.check(words: said, audio: audio)
            guard !slips.isEmpty else { return }
            for (i, word) in slips { tracker.markVowelSlip(i, said: word) }
            publish()
        }
    }

    private func handle(_ event: SpeechSourceEvent) {
        guard !stopped else { return }
        if case .failed = status { return }
        switch event {
        case .downloading(let p):
            status = .downloading(p)
        case .loadingModel:
            status = .loadingModel
        case .listening:
            status = .listening
            tracker.restartClock(at: now)
            startClock()
        }
    }

    private func fail(_ error: Error) {
        guard !stopped else { return }
        status = .failed(VoiceFailure(error))
        clock?.cancel()
        source.stop()
    }

    /// While listening: show the "lost" cue during a long pause (no result
    /// arrives at all then), and reveal the next word when stuck.
    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard !stopped else { return }
        tracker.noteSilence(at: now)
        if let after = stuckRevealAfter, tracker.silence(at: now) > after {
            tracker.revealNext(at: now, as: revealOutcome)
        }
        publish()
    }

    private func publish() {
        if lockState != tracker.lockState { lockState = tracker.lockState }
        let latest = tracker.outcomes
        let nowShown = tracker.shownOutcomes
        let nowHeard = tracker.heard
        guard tracker.cursor != cursor || tracker.anchor != anchor || latest != outcomes
                || nowShown != shown || nowHeard != heard
        else { return }
        cursor = tracker.cursor
        anchor = tracker.anchor
        if latest != outcomes { outcomes = latest }
        shown = nowShown
        heard = nowHeard
        reveal = RevealState(layout: layout, anchor: anchor, cursor: cursor, outcomes: nowShown, heard: nowHeard)
        let mistakes = nowShown.values.filter(\.isMistake).count
        if mistakes != mistakeCount { mistakeCount = mistakes }
    }
}
