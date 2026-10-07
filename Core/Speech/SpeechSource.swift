import Foundation

/// Produces a stream of recognized text fragments. The engine (Apple, file,
/// mock) is hidden behind this so the tracker/UI never import Speech directly.
protocol SpeechSource: AnyObject {
    /// An async stream of recognized fragments, oldest first.
    var fragments: AsyncStream<TranscriptFragment> { get }
    /// Begin producing. Throws if permission/engine setup fails.
    func start() async throws
    /// Stop producing and finish the stream.
    func stop()
}

/// A scripted source for tests: replays a fixed list of fragments.
final class MockSpeechSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    private let script: [TranscriptFragment]

    init(script: [TranscriptFragment]) {
        self.script = script
        (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self)
    }

    func start() async throws {
        // AsyncStream.makeStream uses an unbounded buffer, so all yields are
        // queued even if the consumer hasn't started iterating — a test may call
        // start() first and then drain fragments. Don't copy this
        // produce-then-finish shape to a real, unbuffered source.
        for fragment in script { continuation.yield(fragment) }
        continuation.finish()
    }

    func stop() { continuation.finish() }
}
