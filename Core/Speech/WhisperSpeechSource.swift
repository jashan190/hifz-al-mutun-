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
    private let lastUpdate = OSAllocatedUnfairLock(initialState: Date())
    #endif

    /// Audio from somewhere other than the microphone (tests feed a file).
    private let audioInput: (any AudioProcessing)?
    /// What records, once running: its samples back the final fragments' audio.
    private var recorder: (any AudioProcessing)?
    /// Attach each final fragment's audio (for the vowel check). Set before
    /// `start()`.
    var keepsAudio = false

    init(model: WhisperModel = .selected, audioInput: (any AudioProcessing)? = nil) {
        self.model = model
        self.audioInput = audioInput
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
        if audioInput == nil {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw SpeechSourceError.micNotAuthorized
            }
        }
        try checkNotStopped()

        let whisper = try await WhisperEngine.shared.whisper(
            for: model,
            progress: { [onEvent] in onEvent?(.downloading($0)) },
            loading: { [onEvent] in onEvent?(.loadingModel) })
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
        recorder = audioInput ?? whisper.audioProcessor
        let streamer = AudioStreamTranscriber(
            audioEncoder: whisper.audioEncoder,
            featureExtractor: whisper.featureExtractor,
            segmentSeeker: whisper.segmentSeeker,
            textDecoder: whisper.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: audioInput ?? whisper.audioProcessor,
            decodingOptions: options,
            // Confirm a segment once one newer segment follows it (default 2):
            // finals land a pass sooner and each pass re-reads less audio.
            requiredSegmentsForConfirmation: 1,
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
        if var (last, span) = emitter.withLock({ e in e.flush().map { ($0, e.finalSpan) } }) {
            if keepsAudio, let recorder, let span { last.audio = Self.clip(recorder.audioSamples, span) }
            log(last)
            continuation.yield(last)
        }
        continuation.finish()
    }

    private func receive(_ state: AudioStreamTranscriber.State) {
        func segments(_ list: [TranscriptionSegment]) -> [WhisperFragments.Segment] {
            list.map { .init(text: $0.text, start: $0.start, end: $0.end) }
        }
        let confirmed = segments(state.confirmedSegments)
        let unconfirmed = segments(state.unconfirmedSegments)
        var (out, span) = emitter.withLock { e in (e.update(confirmed: confirmed, unconfirmed: unconfirmed), e.finalSpan) }
        if keepsAudio, let recorder, let span, let k = out.firstIndex(where: \.isFinal) {
            out[k].audio = Self.clip(recorder.audioSamples, span)
        }
        #if DEBUG
        if !out.isEmpty {
            // How far behind live speech words appear: the time since the last
            // update is about one transcription pass (the lag), next to how
            // much audio this pass covered.
            let now = Date()
            let gap = now.timeIntervalSince(lastUpdate.withLock { last in defer { last = now }; return last })
            let heard = Float(state.lastBufferSize) / Float(WhisperKit.sampleRate)
            Self.log.debug("pass \(gap, format: .fixed(precision: 1), privacy: .public)s after the last, audio to \(heard, format: .fixed(precision: 1), privacy: .public)s")
        }
        #endif
        for fragment in out {
            log(fragment)
            continuation.yield(fragment)
        }
    }

    /// The samples of `span` (seconds), with a quarter second either side so
    /// the first and last sounds aren't cut.
    private static func clip(_ samples: ContiguousArray<Float>, _ span: ClosedRange<Float>) -> [Float] {
        let rate = Float(WhisperKit.sampleRate)
        let from = max(0, Int((span.lowerBound - 0.25) * rate))
        let to = min(samples.count, Int((span.upperBound + 0.25) * rate))
        return from < to ? Array(samples[from..<to]) : []
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
        case .starting:
            // Nothing is recording yet; a download or load still in flight
            // finishes in the background (WhisperEngine) for next time.
            continuation.finish()
        case .stopped:
            break
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
