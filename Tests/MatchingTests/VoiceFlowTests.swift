import Testing
import Foundation
@testable import HifzAlMutun

/// The session and controller around the tracker: status, failures, flags.
@MainActor
@Suite struct VoiceFlowTests {
    private func matn() -> Matn {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) })
        }
        let b1 = Bayt(number: 1, sadr: hemi(["يقول", "راجي"]), ajuz: hemi(["عفو", "رب"]))
        let b2 = Bayt(number: 2, sadr: hemi(["قادر", "محمد"]), ajuz: hemi(["الحمد", "لله"]))
        return Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t", author: "a", meter: "m",
                    baytsPerPage: 1, pageCount: 2, baytCount: 2,
                    pages: [MatnPage(page: 1, items: [.bayt(b1)]), MatnPage(page: 2, items: [.bayt(b2)])],
                    babs: [], reviewNotes: [])
    }

    /// Let queued main-actor work (source events, sinks) run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func failureToStartIsReported() async {
        let mock = MockSpeechSource(script: [], failure: .micNotAuthorized)
        let session = RecitationSession(index: RecitationIndex(matn: matn()), source: mock, startWordIndex: 0)
        session.start()
        await settle()
        #expect(session.status == .failed(.micDenied))
    }

    @Test func listeningOnceTheSourceIsLive() async {
        let mock = MockSpeechSource(script: [.init(text: "يقول", isFinal: true)], interval: .milliseconds(1))
        let session = RecitationSession(index: RecitationIndex(matn: matn()), source: mock, startWordIndex: 0)
        session.start()
        await settle()
        #expect(session.status == .listening)
        #expect(session.cursor == 1)
        session.stop()
        #expect(session.status == .idle)
    }

    @Test func mistakesFlagAndCorrectRecitationUnflags() async {
        let store = FlagStore.inMemory()
        let voice = VoiceController()
        // Skip راجي: it gets flagged.
        UserDefaults.standard.set("يقول|عفو", forKey: "debugRecite")
        defer { UserDefaults.standard.removeObject(forKey: "debugRecite") }
        voice.start(matn: matn(), fromPage: 1, flags: store)
        await settle()
        let rajiKey = FlagKey(bayt: 1, half: .sadr, wordIndex: 1)
        #expect(store.isFlagged("t", rajiKey))
        // "Not a mistake" removes it.
        voice.dismissMistake(bayt: 1, half: .sadr, wordIndex: 1)
        await settle()
        #expect(!store.isFlagged("t", rajiKey))
    }

    @Test func manualSittingRevealsByTapWithoutFlagging() async {
        let store = FlagStore.inMemory()
        let voice = VoiceController()
        voice.start(matn: matn(), fromPage: 2, flags: store, manual: true)
        await settle()
        voice.revealNext()
        await settle()
        #expect(voice.reveal?.revealedWords(bayt: 2, half: .sadr) == 1)
        #expect(store.count(for: "t") == 0)   // reviewing by tap isn't a mistake
        #expect(!voice.isLive && voice.isActive)
    }

    // B1 in the UI: a download still finishing, or a "listening" that crossed
    // paths with the stop, must not bring a stopped session back.
    @Test func lateEventsDontReviveAStoppedSession() async {
        let source = HeldSource()
        let session = RecitationSession(index: RecitationIndex(matn: matn()), source: source, startWordIndex: 0)
        session.start()
        await settle()
        session.stop()
        source.onEvent?(.downloading(0.5))
        source.onEvent?(.loadingModel)
        source.onEvent?(.listening)
        await settle()
        #expect(session.status == .idle)
    }

    @Test func loadingTheModelIsShown() async {
        let source = HeldSource()
        let session = RecitationSession(index: RecitationIndex(matn: matn()), source: source, startWordIndex: 0)
        session.start()
        await settle()
        source.onEvent?(.downloading(0.4))
        await settle()
        #expect(session.status == .downloading(0.4))
        source.onEvent?(.loadingModel)
        await settle()
        #expect(session.status == .loadingModel)
        source.onEvent?(.listening)
        await settle()
        #expect(session.status == .listening)
        session.stop()
    }

    @Test func failedDownloadIsReported() async {
        let mock = MockSpeechSource(script: [], failure: .modelDownloadFailed)
        let session = RecitationSession(index: RecitationIndex(matn: matn()), source: mock, startWordIndex: 0)
        session.start()
        await settle()
        #expect(session.status == .failed(.downloadFailed))
    }

    // After a stop the results stay put: swiping back or tapping a blank to
    // look at them must not reset or add to them.
    @Test func stoppedResultsAreLeftAlone() async {
        let store = FlagStore.inMemory()
        let voice = VoiceController()
        UserDefaults.standard.set("يقول|عفو", forKey: "debugRecite")
        defer { UserDefaults.standard.removeObject(forKey: "debugRecite") }
        voice.start(matn: matn(), fromPage: 1, flags: store)
        await settle()
        voice.stop()
        let before = voice.reveal?.outcome(bayt: 1, half: .sadr, wordIndex: 1)
        voice.jump(toPage: 1)
        voice.revealNext()
        await settle()
        #expect(before == .skipped)
        #expect(voice.reveal?.outcome(bayt: 1, half: .sadr, wordIndex: 1) == .skipped)
        #expect(voice.reveal?.revealedWords(bayt: 1, half: .ajuz) == 1)   // nothing new revealed
        #expect(voice.summary?.mistakes == 1)
    }

    @Test func voiceFailureFallsBackToTapKeepingTheReason() async {
        let voice = VoiceController()
        UserDefaults.standard.set("mic", forKey: "debugVoiceFail")
        defer { UserDefaults.standard.removeObject(forKey: "debugVoiceFail") }
        voice.start(matn: matn(), fromPage: 1, flags: nil)
        await settle()
        #expect(voice.status == .failed(.micDenied))
        voice.fallBackToManual(matn: matn(), page: 1)
        await settle()
        #expect(voice.isManual && voice.isActive)
        #expect(voice.voiceFailure == .micDenied)
    }

    @Test func pageTurnsOnceThePageIsDone() async {
        let voice = VoiceController()
        UserDefaults.standard.set("يقول راجي عفو رب", forKey: "debugRecite")
        defer { UserDefaults.standard.removeObject(forKey: "debugRecite") }
        voice.start(matn: matn(), fromPage: 1, flags: nil)
        await settle()
        #expect(voice.page(forCursor: voice.cursor) == 2)   // last word of page 1 recited
    }

    @Test func clearAllRemovesEveryFlag() {
        let store = FlagStore.inMemory()
        store.setFlag(true, matnID: "a", FlagKey(bayt: 1, half: .sadr, wordIndex: 0))
        store.setFlag(true, matnID: "b", FlagKey(bayt: 2, half: .ajuz, wordIndex: 1))
        store.clearAll()
        #expect(store.count(for: "a") == 0 && store.count(for: "b") == 0)
    }

    @Test func flagStoreRoundTrip() {
        let store = FlagStore.inMemory()
        let key = FlagKey(bayt: 3, half: .ajuz, wordIndex: 2)
        store.setFlag(true, matnID: "m", key)
        #expect(store.isFlagged("m", key) && store.count(for: "m") == 1)
        store.setFlag(false, matnID: "m", key)
        #expect(!store.isFlagged("m", key) && store.count(for: "m") == 0)
    }
}

/// A source that never produces anything and never finishes on its own, so a
/// test can send events at it after the session has stopped.
private final class HeldSource: SpeechSource {
    let fragments: AsyncStream<TranscriptFragment>
    var onEvent: (@Sendable (SpeechSourceEvent) -> Void)?
    private let continuation: AsyncStream<TranscriptFragment>.Continuation
    init() { (fragments, continuation) = AsyncStream.makeStream(of: TranscriptFragment.self) }
    func start() async throws {}
    func stop() { continuation.finish() }
}
