import Testing
import Foundation
import WhisperKit
@testable import HifzAlMutun

/// Whisper output → tracker fragments, and what the tracker makes of a real
/// Whisper transcript of the bundled Shatibiyyah clip (bayts 1–10).
@Suite struct WhisperTests {
    // MARK: - Fragments

    @Test func unconfirmedTextIsVolatileAndReplacedWhole() {
        var f = WhisperFragments()
        #expect(f.update(confirmed: [], unconfirmed: [" بدأت"]) == [.init(text: "بدأت", isFinal: false)])
        #expect(f.update(confirmed: [], unconfirmed: [" بدأت ببسم الله"]) == [.init(text: "بدأت ببسم الله", isFinal: false)])
        #expect(f.update(confirmed: [], unconfirmed: [" بدأت ببسم الله"]).isEmpty)   // unchanged: nothing new
    }

    @Test func newlyConfirmedSegmentsAreFinalOnce() {
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: ["أ", "ب", "ج"])
        #expect(f.update(confirmed: ["أ"], unconfirmed: ["ب", "ج"])
                == [.init(text: "أ", isFinal: true), .init(text: "ب ج", isFinal: false)])
        // The same confirmed list again adds nothing final.
        #expect(f.update(confirmed: ["أ"], unconfirmed: ["ب", "ج د"]) == [.init(text: "ب ج د", isFinal: false)])
        #expect(f.update(confirmed: ["أ", "ب"], unconfirmed: ["ج د"])
                == [.init(text: "ب", isFinal: true), .init(text: "ج د", isFinal: false)])
    }

    @Test func aGuessIsResentAfterAFinal() {
        // The tracker drops its tentative state when a final lands, so the
        // guess must come again even if its text didn't change.
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: ["ج"])
        #expect(f.update(confirmed: ["أ"], unconfirmed: ["ج"])
                == [.init(text: "أ", isFinal: true), .init(text: "ج", isFinal: false)])
    }

    @Test func stopTurnsTheLastGuessFinal() {
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: ["هو الحر"])
        #expect(f.flush() == .init(text: "هو الحر", isFinal: true))
        #expect(f.flush() == nil)
    }

    @Test func nonSpeechMarkersAreDropped() {
        var f = WhisperFragments()
        #expect(f.update(confirmed: [], unconfirmed: ["[موسيقى]"]).isEmpty)
        #expect(f.update(confirmed: ["(تصفيق)", "بدأت"], unconfirmed: [])
                == [.init(text: "بدأت", isFinal: true)])
    }

    // MARK: - Tracker on a real Whisper transcript

    /// whisperkit-cli 1.1.1, large-v3-v20240930_turbo_632MB, `--language ar`,
    /// on Tests/SpeechTests/Fixtures/shatibiyya_clip.m4a.
    static let turboTranscript = """
        بدأت ببسم الله في النظم أولا تبارك رحمن الرحيم وموئلا وثنيت صلى الله ربي على الرضا محمد المهدى إلى الناس مرسلا وعطرته ثم الصحابة ثم من تلاهم على الإحسان بالخير والبلا وثلثت أن الحمد لله دائما وما ليس مبدوءا به أجذم العلا وبعد فحبل الله فينا كتابه فجاهد به حبل العدى متحبلا وأخلق به إذ ليس يخلق جدة جديدا مواليه على الجد مقبلا وقارئه المرضي قر مثاله كالترجح عليه مريحا وموكلا هو المرتضاء من إذا كان أمة ويممه ظل الرزانة قنقلا هو الحر إن كان الحري حواليا له بتحريه إلى أن تنبلا وإن كتاب الله أوثق شافع وأغنى غناء واهبا متفضلا
        """

    static func shatibiyya() throws -> RecitationIndex {
        let url = try #require(Bundle.main.url(forResource: "shatibiyya", withExtension: "json"))
        return RecitationIndex(matn: try JSONDecoder().decode(Matn.self, from: Data(contentsOf: url)))
    }

    /// Replays a transcript the way the streamer delivers it: growing guesses,
    /// with every few words confirmed.
    static func stream(_ text: String, into tracker: RecitationTracker) {
        let words = text.split(separator: " ").map(String.init)
        var f = WhisperFragments()
        var confirmed: [String] = []
        var t = 0.0
        for chunk in stride(from: 0, to: words.count, by: 4) {
            let segment = words[chunk..<min(words.count, chunk + 4)].joined(separator: " ")
            for n in 1...segment.split(separator: " ").count {      // the guess grows a word at a time
                let partial = segment.split(separator: " ").prefix(n).joined(separator: " ")
                for fragment in f.update(confirmed: confirmed, unconfirmed: [partial]) {
                    tracker.consume(fragment, at: t)
                }
                t += 0.4
            }
            confirmed.append(segment)
        }
        for fragment in f.update(confirmed: confirmed, unconfirmed: []) { tracker.consume(fragment, at: t) }
    }

    @Test func turboTranscriptFollowsTheClip() throws {
        let index = try Self.shatibiyya()
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        Self.stream(Self.turboTranscript, into: tracker)

        let end = try #require(index.firstWordIndex(ofBayt: 11))
        let judged = tracker.outcomes.filter { $0.key < end }
        let mistakes = judged.filter { $0.value.isMistake }
        // Every word of bayts 1–10 is followed to the end. Whisper's misreadings
        // mostly come out amber (unsure); 3 red at the time of writing.
        #expect(tracker.cursor == end)
        #expect(tracker.lockState == .locked)
        #expect(judged.count == end)
        #expect(mistakes.count <= 4, "mistakes: \(mistakes.sorted { $0.key < $1.key })")
    }

    // MARK: - WhisperKit itself (opt-in: downloads 632 MB)

    /// Run with `TEST_RUNNER_WHISPER_E2E=1 xcodebuild test …` (Simulator or
    /// iPhone). Transcribes the clip with the app's model and settings.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISPER_E2E"] == "1"),
          .timeLimit(.minutes(20)))
    func transcribesTheClip() async throws {
        let model = WhisperModel.turbo
        try await model.download { _ in }
        let whisper = try await WhisperKit(WhisperKitConfig(
            modelFolder: model.folder.path, tokenizerFolder: WhisperModel.storage,
            verbose: false, logLevel: .error, load: true, download: false))
        let clip = try #require(Bundle(for: BundleToken.self).url(forResource: "shatibiyya_clip", withExtension: "m4a"))
        let results = try await whisper.transcribe(
            audioPath: clip.path,
            decodeOptions: DecodingOptions(language: "ar", detectLanguage: false, skipSpecialTokens: true))
        let text = results.map(\.text).joined(separator: " ")
        print("WHISPER clip:", text)

        let index = try Self.shatibiyya()
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        Self.stream(text, into: tracker)
        let end = try #require(index.firstWordIndex(ofBayt: 11))
        #expect(tracker.cursor >= end - 2)
        #expect(tracker.outcomes.filter { $0.key < end && $0.value.isMistake }.count <= 12)
    }
}

private final class BundleToken {}
