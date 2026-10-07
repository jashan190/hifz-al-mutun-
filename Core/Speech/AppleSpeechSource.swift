import Foundation
import AVFoundation
import Speech

/// Live-microphone speech source backed by iOS 26's SpeechAnalyzer. Requests
/// permission, captures audio with AVAudioEngine (converting to the analyzer's
/// preferred format), and emits recognizer fragments. Build-verified here; real
/// microphone behaviour is validated on-device.
@available(iOS 26, *)
final class AppleSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let locale: Locale
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var readerTask: Task<Void, Never>?
    private var isRunning = false

    init(locale: Locale = Locale(identifier: "ar")) {
        self.locale = locale
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    /// Begins capture and recognition. NOTE: `analyzer.start(inputSequence:)` does
    /// not return until the input stream finishes (i.e. until `stop()` is called),
    /// so callers must invoke `start()` in its own Task and drive `stop()`
    /// separately — never `await start()` inline expecting it to return promptly.
    func start() async throws {
        guard !isRunning else { return }   // ignore a second start
        try await SpeechModel.requestAuthorization()

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await SpeechModel.ensureInstalled(transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        readerTask = Task { [continuation] in
            do {
                for try await result in transcriber.results {
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

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Drop a buffer we can't convert rather than feed a format-mismatched
            // one to the analyzer. A nil converter means the input already matches.
            let out: AVAudioPCMBuffer? = converter == nil
                ? buffer
                : Self.convert(buffer, using: converter, to: analyzerFormat)
            if let out { self.inputContinuation?.yield(AnalyzerInput(buffer: out)) }
        }
        isRunning = true                 // tap installed; stop() may now tear down
        engine.prepare()
        try engine.start()

        // Blocks until the input stream finishes (see note on start()).
        try await analyzer.start(inputSequence: inputStream)
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
        guard isRunning else { return }   // safe to call before start() / twice
        isRunning = false

        // 1. Stop feeding audio: remove the tap, stop the engine, end the input stream.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()
        try? AVAudioSession.sharedInstance().setActive(false)

        // 2. Finalise the analyzer so it emits any last result, which completes
        //    `transcriber.results`; the reader loop then exits and finishes the
        //    fragments stream itself (we don't cancel it — that would drop the
        //    final word — and we don't finish the stream here to avoid racing it).
        let analyzer = self.analyzer
        self.analyzer = nil
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
    }
}
