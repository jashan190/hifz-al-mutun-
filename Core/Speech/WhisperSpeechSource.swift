import Foundation
import AVFoundation
import WhisperKit
import os

/// Live-microphone speech source backed by WhisperKit (OpenAI's Whisper,
/// compiled for the phone's Neural Engine). Downloads the model on first use,
/// then streams: WhisperKit records, re-transcribes about once a second, and
/// `WhisperFragments` turns each state into tracker fragments.
final class WhisperSpeechSource: SpeechSource, @unchecked Sendable {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let model: WhisperModel
    private var streamer: AudioStreamTranscriber?
    private let emitter = OSAllocatedUnfairLock(initialState: WhisperFragments())

    /// Where the source is in its life. `start()` awaits permission, a
    /// possible download and the model load, and `stop()` can arrive at any
    /// point in between (on another thread), so the phase lives behind a lock
    /// and `start()` re-checks it after every await.
    private enum Phase { case idle, starting, running, stopped }
    private let phase = OSAllocatedUnfairLock(initialState: Phase.idle)
    /// Set once the streamer's loop has returned.
    private let streamEnded = OSAllocatedUnfairLock(initialState: false)

    #if DEBUG
    private static let log = Logger(subsystem: "com.farhan.hifzalmutun", category: "speech")
    #endif

    init(model: WhisperModel = .selected) {
        self.model = model
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    /// Begins capture and recognition. Like the streamer it wraps, it doesn't
    /// return until `stop()` (or a recording error), so callers run it in its
    /// own Task.
    func start() async throws {
        let began = phase.withLock { p -> Bool in
            guard p == .idle else { return false }   // ignore a second start
            p = .starting
            return true
        }
        guard began else { return }
        do {
            try await run()
        } catch {
            phase.withLock { $0 = .stopped }
            continuation.finish()
            throw error
        }
    }

    private func run() async throws {
        // WhisperKit's own start returns silently when the mic is refused, so
        // ask first and say why.
        guard await AVAudioApplication.requestRecordPermission() else {
            throw SpeechSourceError.micNotAuthorized
        }
        try checkNotStopped()

        try await model.download { [onEvent] in onEvent?(.downloading($0)) }
        try checkNotStopped()

        onEvent?(.loadingModel)
        let config = WhisperKitConfig(
            modelFolder: model.folder.path,
            tokenizerFolder: WhisperModel.storage,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let whisper: WhisperKit
        do {
            whisper = try await WhisperKit(config)
        } catch {
            // Most likely the tokenizer, fetched on the first load.
            throw SpeechSourceError.modelDownloadFailed
        }
        try checkNotStopped()
        guard let tokenizer = whisper.tokenizer else { throw SpeechSourceError.modelDownloadFailed }

        let options = DecodingOptions(
            task: .transcribe,
            language: "ar",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false     // confirmation needs segment ends
        )
        let streamer = AudioStreamTranscriber(
            audioEncoder: whisper.audioEncoder,
            featureExtractor: whisper.featureExtractor,
            segmentSeeker: whisper.segmentSeeker,
            textDecoder: whisper.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisper.audioProcessor,
            decodingOptions: options,
            useVAD: true                 // don't transcribe silence (Whisper invents text on it)
        ) { [weak self] _, state in
            self?.receive(state)
        }
        self.streamer = streamer

        // Last chance for a stop that arrived during setup.
        let stillWanted = phase.withLock { p -> Bool in
            guard p == .starting else { return false }
            p = .running
            return true
        }
        guard stillWanted else { throw CancellationError() }
        onEvent?(.listening)

        // Records and transcribes until stopStreamTranscription() (or an error,
        // which WhisperKit logs and ends the loop on). Either way the sitting's
        // last guess becomes final and the stream ends.
        try await streamer.startStreamTranscription()
        streamEnded.withLock { $0 = true }
        phase.withLock { $0 = .stopped }
        if let last = emitter.withLock({ $0.flush() }) {
            log(last)
            continuation.yield(last)
        }
        continuation.finish()
    }

    private func receive(_ state: AudioStreamTranscriber.State) {
        let confirmed = state.confirmedSegments.map(\.text)
        let unconfirmed = state.unconfirmedSegments.map(\.text)
        let out = emitter.withLock { $0.update(confirmed: confirmed, unconfirmed: unconfirmed) }
        for fragment in out {
            log(fragment)
            continuation.yield(fragment)
        }
    }

    private func log(_ fragment: TranscriptFragment) {
        #if DEBUG
        Self.log.debug("\(fragment.isFinal ? "FINAL" : "volatile", privacy: .public) \(fragment.text, privacy: .public)")
        #endif
    }

    /// Throws if `stop()` arrived while `start()` was awaiting.
    private func checkNotStopped() throws {
        if phase.withLock({ $0 == .stopped }) { throw CancellationError() }
    }

    func stop() {
        let previous = phase.withLock { p -> Phase in
            let was = p
            p = .stopped
            return was
        }
        switch previous {
        case .idle:
            continuation.finish()      // never started: just end the stream
        case .starting, .stopped:
            break                      // start() sees `.stopped` at its next check and ends the stream
        case .running:
            // Ends the streamer's loop; start() then flushes and finishes. A
            // stop that reaches the streamer before its loop begins would be
            // undone by the loop starting, so repeat until the loop has ended.
            guard let streamer else { return }
            Task { [streamEnded] in
                for _ in 0..<50 where !streamEnded.withLock({ $0 }) {
                    await streamer.stopStreamTranscription()
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }
}
