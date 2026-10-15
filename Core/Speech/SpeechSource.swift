import Foundation

/// Progress a source reports while it gets ready, before any fragment.
enum SpeechSourceEvent: Equatable {
    /// Fetching the on-device model, 0…1.
    case downloading(Double)
    /// The microphone (or file) is live; fragments will follow.
    case listening
}

/// Produces a stream of recognized text fragments. The engine (Apple, file,
/// mock) is hidden behind this so the tracker/UI never import Speech directly.
protocol SpeechSource: AnyObject {
    /// An async stream of recognized fragments, oldest first.
    var fragments: AsyncStream<TranscriptFragment> { get }
    /// Called (on any thread) as the source gets ready.
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)? { get set }
    /// Begin producing. Throws if permission/engine setup fails.
    func start() async throws
    /// Stop producing and finish the stream. Safe at any time, including while
    /// `start()` is still waiting on permission or a model download.
    func stop()
}

/// A scripted source for tests and the DEBUG `-debugRecite` harness: replays a
/// fixed list of fragments, optionally paced like live speech, or fails.
final class MockSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let script: [TranscriptFragment]
    private let interval: Duration?
    private let failure: SpeechSourceError?

    init(script: [TranscriptFragment], interval: Duration? = nil, failure: SpeechSourceError? = nil) {
        self.script = script
        self.interval = interval
        self.failure = failure
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        if let failure { continuation.finish(); throw failure }
        onEvent?(.listening)
        // AsyncStream.makeStream uses an unbounded buffer, so all yields are
        // queued even if the consumer hasn't started iterating — a test may call
        // start() first and then drain fragments.
        for fragment in script {
            if let interval { try? await Task.sleep(for: interval) }
            if Task.isCancelled { break }
            continuation.yield(fragment)
        }
        if interval == nil { continuation.finish() }   // paced: stays "live" until stopped
    }

    func stop() { continuation.finish() }
}

/// A source that hears nothing: a tap-to-reveal sitting when voice isn't
/// available (no microphone permission, no Arabic model). Live until stopped.
final class SilentSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation

    init() {
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws { onEvent?(.listening) }
    func stop() { continuation.finish() }
}
