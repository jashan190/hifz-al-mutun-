import Foundation
import AVFoundation
import Speech

/// Transcribes an audio file through iOS 26's SpeechAnalyzer and emits the
/// recognizer's fragments. Used for the engine spike and fixture accuracy tests,
/// and as the simulator-friendly dev loop (no live mic needed). Shares the asset
/// install path with the live source via `SpeechModel`.
final class FileSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let url: URL
    private let locale: Locale
    private var task: Task<Void, Never>?

    init(url: URL, locale: Locale = Locale(identifier: "ar")) {
        self.url = url
        self.locale = locale
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        let transcriber = SpeechTranscriber(
            locale: try await SpeechModel.resolveLocale(locale),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await SpeechModel.ensureInstalled(transcriber) { [onEvent] in onEvent?(.downloading($0)) }
        onEvent?(.listening)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        // Drain results into the stream as the file is analysed.
        task = Task { [continuation] in
            do {
                for try await result in transcriber.results {
                    continuation.yield(.init(text: String(result.text.characters),
                                             isFinal: result.isFinal))
                }
            } catch { }
            continuation.finish()
        }

        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
    }

    func stop() {
        task?.cancel()
        continuation.finish()
    }
}
