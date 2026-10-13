import Foundation
import AVFoundation
import Speech
import os

/// Live-microphone speech source backed by iOS 26's SpeechAnalyzer. Requests
/// permission, captures audio with AVAudioEngine (converting to the analyzer's
/// preferred format), and emits recognizer fragments. Build-verified here; real
/// microphone behaviour is validated on-device.
final class AppleSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let locale: Locale
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var readerTask: Task<Void, Never>?
    private var tapInstalled = false

    /// Where the source is in its life. `start()` awaits permission and a
    /// possible model download, and `stop()` can arrive at any point in
    /// between (on another thread), so the phase lives behind a lock and
    /// `start()` re-checks it after every await.
    private enum Phase { case idle, starting, running, stopped }
    private let phase = OSAllocatedUnfairLock(initialState: Phase.idle)

    #if DEBUG
    private static let log = Logger(subsystem: "com.farhan.hifzalmutun", category: "speech")
    #endif

    init(locale: Locale = Locale(identifier: "ar")) {
        self.locale = locale
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    /// Begins capture and recognition. NOTE: `analyzer.start(inputSequence:)` does
    /// not return until the input stream finishes (i.e. until `stop()` is called),
    /// so callers must invoke `start()` in its own Task and drive `stop()`
    /// separately — never `await start()` inline expecting it to return promptly.
    func start() async throws {
        let began = phase.withLock { p -> Bool in
            guard p == .idle else { return false }   // ignore a second start
            p = .starting
            return true
        }
        guard began else { return }
        do {
            try await startCapture()
        } catch is CancellationError {
            throw CancellationError()      // a stop: already torn down
        } catch {
            // Permission refused, no Arabic model, the engine failed…: release
            // whatever was set up and end the stream, so nothing is left live.
            phase.withLock { $0 = .stopped }
            teardown(analyzerStarted: false)
            throw error
        }
    }

    private func startCapture() async throws {
        try await SpeechModel.requestAuthorization()
        try checkNotStopped()

        let transcriber = SpeechTranscriber(
            locale: try await SpeechModel.resolveLocale(locale),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await SpeechModel.ensureInstalled(transcriber) { [onEvent] in onEvent?(.downloading($0)) }
        try checkNotStopped()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        readerTask = Task { [continuation] in
            do {
                for try await result in transcriber.results {
                    #if DEBUG
                    // Phase A check: does each result cover its own audio range,
                    // and does the next one replace a volatile one?
                    Self.log.debug("""
                        \(result.isFinal ? "FINAL" : "volatile", privacy: .public) \
                        \(result.range.start.seconds, privacy: .public)…\(result.range.end.seconds, privacy: .public) \
                        \(String(result.text.characters), privacy: .public)
                        """)
                    #endif
                    continuation.yield(.init(text: String(result.text.characters),
                                             isFinal: result.isFinal))
                }
            } catch { }
            continuation.finish()
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (inputStream, inputCont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = inputCont

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)   // .duckOthers is invalid for .record
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter: AVAudioConverter? = {
            guard let analyzerFormat, analyzerFormat != inputFormat else { return nil }
            return AVAudioConverter(from: inputFormat, to: analyzerFormat)
        }()

        // The tap runs on the audio thread; it captures the input continuation
        // directly rather than reaching through `self`.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            // Drop a buffer we can't convert rather than feed a format-mismatched
            // one to the analyzer. A nil converter means the input already matches.
            let out: AVAudioPCMBuffer? = converter == nil
                ? buffer
                : Self.convert(buffer, using: converter, to: analyzerFormat)
            if let out { inputCont.yield(AnalyzerInput(buffer: out)) }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()

        // Last chance for a stop that arrived during setup: it found us still
        // `.starting` and left the teardown to us.
        let stillWanted = phase.withLock { p -> Bool in
            guard p == .starting else { return false }
            p = .running
            return true
        }
        guard stillWanted else {
            teardown(analyzerStarted: false)
            throw CancellationError()
        }
        onEvent?(.listening)

        // Blocks until the input stream finishes (see note on start()).
        try await analyzer.start(inputSequence: inputStream)
    }

    /// Throws if `stop()` arrived while `start()` was awaiting, finishing the
    /// fragment stream so anyone draining it can end.
    private func checkNotStopped() throws {
        if phase.withLock({ $0 == .stopped }) {
            continuation.finish()
            throw CancellationError()
        }
    }

    /// Convert a captured buffer to the analyzer's format (sample-rate / layout).
    /// Returns nil to signal the caller to fall back to the raw buffer.
    private static func convert(_ buffer: AVAudioPCMBuffer,
                                using converter: AVAudioConverter?,
                                to format: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard let converter, let format else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
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
            break                      // start() sees `.stopped` at its next check and tears down
        case .running:
            teardown(analyzerStarted: true)
        case .stopped:
            break                      // already stopped
        }
    }

    private func teardown(analyzerStarted: Bool) {
        // 1. Stop feeding audio: remove the tap, stop the engine, end the input stream.
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        inputContinuation?.finish()
        try? AVAudioSession.sharedInstance().setActive(false)

        // 2. Finalise the analyzer so it emits any last result, which completes
        //    `transcriber.results`; the reader loop then exits and finishes the
        //    fragments stream itself (we don't cancel it — that would drop the
        //    final word — and we don't finish the stream here to avoid racing it).
        //    If the analyzer never started there is nothing to finalise: cancel
        //    it and finish the stream directly.
        let analyzer = self.analyzer
        self.analyzer = nil
        if analyzerStarted, let analyzer {
            Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        } else {
            readerTask?.cancel()
            continuation.finish()
            if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        }
    }
}
