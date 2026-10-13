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

    @Test func manualSittingRevealsByTap() async {
        let store = FlagStore.inMemory()
        let voice = VoiceController()
        voice.start(matn: matn(), fromPage: 2, flags: store, manual: true)
        voice.revealNext()
        await settle()
        #expect(voice.reveal?.revealedWords(bayt: 2, half: .sadr) == 1)
        #expect(store.isFlagged("t", FlagKey(bayt: 2, half: .sadr, wordIndex: 0)))  // help is flagged
        #expect(!voice.isLive)
    }

    @Test func pageTurnsOnceThePageIsDone() async {
        let voice = VoiceController()
        UserDefaults.standard.set("يقول راجي عفو رب", forKey: "debugRecite")
        defer { UserDefaults.standard.removeObject(forKey: "debugRecite") }
        voice.start(matn: matn(), fromPage: 1, flags: nil)
        await settle()
        #expect(voice.page(forCursor: voice.cursor) == 2)   // last word of page 1 recited
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
