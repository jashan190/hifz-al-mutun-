import Testing
import Foundation
import WhisperKit
import AVFoundation
import CoreML
import os
@testable import HifzAlMutun

/// Whisper output → tracker fragments, and what the tracker makes of a real
/// Whisper transcript of the bundled Shatibiyyah clip (bayts 1–10).
@Suite struct WhisperTests {
    // MARK: - Fragments

    /// Segments one second each, in order: seg("أ", 0) covers 0–1 s.
    private func seg(_ text: String, _ at: Float) -> WhisperFragments.Segment {
        .init(text: text, start: at, end: at + 1)
    }

    @Test func unconfirmedTextIsVolatileAndReplacedWhole() {
        var f = WhisperFragments()
        #expect(f.update(confirmed: [], unconfirmed: [seg(" بدأت", 0)]) == [.init(text: "بدأت", isFinal: false)])
        #expect(f.update(confirmed: [], unconfirmed: [seg(" بدأت ببسم الله", 0)])
                == [.init(text: "بدأت ببسم الله", isFinal: false)])
        #expect(f.update(confirmed: [], unconfirmed: [seg(" بدأت ببسم الله", 0)]).isEmpty)   // unchanged
    }

    @Test func newlyConfirmedSegmentsAreFinalOnce() {
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: [seg("أ", 0), seg("ب", 1), seg("ج", 2)])
        #expect(f.update(confirmed: [seg("أ", 0)], unconfirmed: [seg("ب", 1), seg("ج", 2)])
                == [.init(text: "أ", isFinal: true), .init(text: "ب ج", isFinal: false)])
        // The same confirmed list again adds nothing final.
        #expect(f.update(confirmed: [seg("أ", 0)], unconfirmed: [seg("ب", 1), seg("ج د", 2)])
                == [.init(text: "ب ج د", isFinal: false)])
        #expect(f.update(confirmed: [seg("أ", 0), seg("ب", 1)], unconfirmed: [seg("ج د", 2)])
                == [.init(text: "ب", isFinal: true), .init(text: "ج د", isFinal: false)])
    }

    @Test func aGuessIsResentAfterAFinal() {
        // The tracker drops its tentative state when a final lands, so the
        // guess must come again even if its text didn't change.
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: [seg("ج", 1)])
        #expect(f.update(confirmed: [seg("أ", 0)], unconfirmed: [seg("ج", 1)])
                == [.init(text: "أ", isFinal: true), .init(text: "ج", isFinal: false)])
    }

    @Test func aStaleGuessDoesntRepeatConfirmedWords() {
        // WhisperKit sets the confirmed list one step before the new guess:
        // for that update the guess still holds the words just confirmed.
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: [seg("أ", 0), seg("ب", 1), seg("ج", 2)])
        #expect(f.update(confirmed: [seg("أ", 0)], unconfirmed: [seg("أ", 0), seg("ب", 1), seg("ج", 2)])
                == [.init(text: "أ", isFinal: true), .init(text: "ب ج", isFinal: false)])
        // Then the real guess lands: same text, nothing new.
        #expect(f.update(confirmed: [seg("أ", 0)], unconfirmed: [seg("ب", 1), seg("ج", 2)]).isEmpty)
    }

    @Test func stopTurnsTheLastGuessFinal() {
        var f = WhisperFragments()
        _ = f.update(confirmed: [], unconfirmed: [seg("هو الحر", 0)])
        #expect(f.flush() == .init(text: "هو الحر", isFinal: true))
        #expect(f.finalSpan == 0...1)                    // its audio, for the vowel check
        #expect(f.flush() == nil)
    }

    @Test func silenceHallucinationsAreDropped() {
        // Both heard from the Simulator's microphone in a quiet room.
        var f = WhisperFragments()
        #expect(f.update(confirmed: [], unconfirmed: [seg("ترجمة نانسي قنقر", 0)]).isEmpty)
        #expect(f.update(confirmed: [], unconfirmed: [seg("موسيقى شكراً لك", 0)]).isEmpty)
        #expect(f.update(confirmed: [], unconfirmed: [seg("بدأت ببسم الله", 0)]) == [.init(text: "بدأت ببسم الله", isFinal: false)])
    }

    @Test func nonSpeechMarkersAreDropped() {
        var f = WhisperFragments()
        #expect(f.update(confirmed: [], unconfirmed: [seg("[موسيقى]", 0)]).isEmpty)
        #expect(f.update(confirmed: [seg("(تصفيق)", 0), seg("بدأت", 1)], unconfirmed: [])
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
    /// `onUpdate` gets, after each fragment, how many transcript words the
    /// recognizer has delivered so far.
    static func stream(_ text: String, into tracker: RecitationTracker,
                       onUpdate: (Int) -> Void = { _ in }) {
        let words = text.split(separator: " ").map(String.init)
        var f = WhisperFragments()
        var confirmed: [WhisperFragments.Segment] = []
        var t = 0.0
        for chunk in stride(from: 0, to: words.count, by: 4) {
            let segment = Array(words[chunk..<min(words.count, chunk + 4)])
            let at = Float(chunk)                                     // a second a word
            for n in 1...segment.count {                              // the guess grows a word at a time
                let partial = WhisperFragments.Segment(text: segment.prefix(n).joined(separator: " "),
                                                       start: at, end: at + Float(n))
                for fragment in f.update(confirmed: confirmed, unconfirmed: [partial]) {
                    tracker.consume(fragment, at: t)
                    onUpdate(chunk + n)
                }
                t += 0.4
            }
            confirmed.append(.init(text: segment.joined(separator: " "), start: at, end: at + Float(segment.count)))
        }
        for fragment in f.update(confirmed: confirmed, unconfirmed: []) {
            tracker.consume(fragment, at: t)
            onUpdate(words.count)
        }
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

    /// The live path: the clip fed at real-time pace through WhisperKit's
    /// streamer (1 s passes, VAD, confirmation) and `WhisperSpeechSource`
    /// into the tracker, then stopped — as with the microphone. Opt-in like
    /// the test above; takes about 90 s.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISPER_E2E"] == "1"),
          .timeLimit(.minutes(20)))
    func streamsTheClipLive() async throws {
        let clip = try #require(Bundle(for: BundleToken.self).url(forResource: "shatibiyya_clip", withExtension: "m4a"))
        let audio = try FileFedAudio(path: clip.path)
        let source = WhisperSpeechSource(model: .turbo, audioInput: audio)
        let index = try Self.shatibiyya()
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)

        let started = Date()
        let start = Task { try await source.start() }
        let drain = Task { () -> (finals: Int, lostWhileReciting: Int, flashed: Set<Int>) in
            var finals = 0, lost = 0
            var everShown: Set<Int> = []
            for await fragment in source.fragments {
                let t = Date().timeIntervalSince(started)
                tracker.consume(fragment, at: t)
                for (i, o) in tracker.shownOutcomes where o.isMistake { everShown.insert(i) }
                if fragment.isFinal { finals += 1 }
                if tracker.lockState == .lost { lost += 1 }
                print("STREAM \(String(format: "%5.1f", t)) \(fragment.isFinal ? "FINAL   " : "volatile") \(fragment.text)")
            }
            // Shown red at some point, but not in the end: a mark and a beep
            // that were taken back.
            return (finals, lost, everShown.subtracting(tracker.outcomes.filter { $0.value.isMistake }.keys))
        }
        // Wait for the clip to play through, then stop as the mic button does.
        while !audio.finished { try await Task.sleep(for: .milliseconds(200)) }
        try await Task.sleep(for: .seconds(3))
        source.stop()
        let (finals, lost, flashed) = await drain.value
        _ = try? await start.value

        let end = try #require(index.firstWordIndex(ofBayt: 11))
        let mistakes = tracker.outcomes.filter { $0.key < end && $0.value.isMistake }
        print("STREAM flashed red then cleared: \(flashed.sorted().map { index.normalizedWords[$0] })")
        #expect(flashed.count <= 1)
        print("STREAM cursor \(tracker.cursor)/\(end), finals \(finals), lost \(lost), mistakes \(mistakes.sorted { $0.key < $1.key })")
        #expect(finals > 0)
        #expect(tracker.cursor >= end - 2)
        #expect(mistakes.count <= 12)
    }

    /// Any recording streamed live from a matn's start: prints each fragment
    /// and how each word of the first four bayts came out, and saves the
    /// fragments (with their times) for `TrackerReplayTests` to replay.
    /// RECORDING=<audio path> RECORDING_MATN=<matn id> [RECORDING_OUT=<json path>].
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECORDING"] != nil), .timeLimit(.minutes(30)))
    @MainActor func aRecordingFromDisk() async throws {
        let env = ProcessInfo.processInfo.environment
        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == env["RECORDING_MATN"] })
        let index = RecitationIndex(matn: matn)
        let audio = try FileFedAudio(path: env["RECORDING"]!)
        let source = WhisperSpeechSource(model: .turbo, audioInput: audio)
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)

        let started = Date()
        let lastFragment = OSAllocatedUnfairLock(initialState: Date())
        let startEnded = OSAllocatedUnfairLock(initialState: false)
        let start = Task {
            defer { startEnded.withLock { $0 = true } }   // also if it fails to start
            try await source.start()
        }
        let drain = Task { () -> [[String: Any]] in
            var log: [[String: Any]] = []
            for await fragment in source.fragments {
                let t = Date().timeIntervalSince(started)
                lastFragment.withLock { $0 = Date() }
                tracker.consume(fragment, at: t)
                log.append(["t": t, "final": fragment.isFinal, "text": fragment.text])
                let shown = tracker.shownOutcomes.filter { $0.value.isMistake }.keys.sorted().map { index.normalizedWords[$0] }
                print("STREAM \(String(format: "%5.1f", t)) \(fragment.isFinal ? "FINAL   " : "volatile") \(fragment.text)  RED \(shown)")
            }
            return log
        }
        // The Simulator's passes are seconds apart: wait for the last of the
        // audio to be transcribed (no new fragment for 20 s), then stop.
        while !startEnded.withLock({ $0 }),
              !audio.finished || lastFragment.withLock({ Date().timeIntervalSince($0) }) < 20 {
            try await Task.sleep(for: .milliseconds(500))
        }
        source.stop()
        let log = await drain.value
        _ = try? await start.value
        if let out = env["RECORDING_OUT"] {
            try JSONSerialization.data(withJSONObject: ["matn": matn.id, "fragments": log]).write(to: URL(fileURLWithPath: out))
        }
        let end = index.firstWordIndex(ofBayt: 5) ?? index.displayWords.count
        print((0..<end).map { i in
            "RECORDING bayt \(index.refs[i].bayt) \(index.displayWords[i]): \(tracker.outcomes[i].map { "\($0)" } ?? "—")"
        }.joined(separator: "\n"))
    }

    /// The vowel check on the live path: the correct clip streamed through
    /// Whisper into a session that checks the harakat of each settled
    /// passage, using the audio its final results carry. Most words must be
    /// checked, and where the model can run (a Mac or phone, VOWEL_MODEL=<path>)
    /// a correct recitation must come out (almost) without vowel slips. In
    /// the Simulator, whose Core ML can't run the model, each check's words
    /// and audio are written to a folder for `Tools/vowels/swift` to judge on
    /// the Mac. Needs WHISPER_E2E=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISPER_E2E"] == "1"), .timeLimit(.minutes(30)))
    @MainActor func vowelCheckIsQuietOnTheCorrectClip() async throws {
        // VOWEL_CLIP=shatibiyya_clip_skips: the clip with two words cut out,
        // so passages are split into runs around them.
        let name = ProcessInfo.processInfo.environment["VOWEL_CLIP"] ?? "shatibiyya_clip"
        let clip = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "m4a"))
        let audio = try FileFedAudio(path: clip.path)
        let source = WhisperSpeechSource(model: .turbo, audioInput: audio)
        source.keepsAudio = true
        let index = try Self.shatibiyya()
        let phonemes = try #require(PhonemeIndex(matnID: "shatibiyya", index: index))
        let recorder = ClipRecorder()
        let hearer: any PhonemeHearing = VowelTests.canRunModel
            ? try PhonemeModel(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOWEL_MODEL"]!))
            : recorder
        let checker = VowelChecker(model: hearer, phonemes: phonemes, written: index.displayWords)
        let session = RecitationSession(index: index, source: source, startWordIndex: 0)
        session.stuckRevealAfter = nil
        session.vowels = checker

        session.start()
        while !audio.finished { try await Task.sleep(for: .milliseconds(200)) }
        try await Task.sleep(for: .seconds(3))
        session.stop()
        try await Task.sleep(for: .seconds(20))      // the last checks

        let end = try #require(index.firstWordIndex(ofBayt: 11))
        let checks = await checker.checked
        let judged = Dictionary(grouping: session.outcomes.filter { $0.key < end }.values) { "\($0)".prefix(7) }.mapValues(\.count)
        let words = checks.joined().joined().count
        print("VOWELS \(checks.count) checks, \(checks.joined().count) runs, over \(words)/\(end) words; outcomes \(judged)")
        #expect(words >= end / 2)
        if VowelTests.canRunModel {
            let slips = session.outcomes.filter {
                guard case .wrong(let said) = $0.value else { return false }
                return ArabicNormalize.normalize(said) == index.normalizedWords[$0.key]
            }
            print("VOWELS slips \(slips.keys.sorted().map { "\(index.displayWords[$0]) → \(slips[$0]!)" })")
            #expect(slips.count <= 2)
        } else {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vowel-checks")
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let clips = recorder.clips
            #expect(clips.count == checks.count)
            var entries: [[String: Any]] = []
            for (k, (runs, samples)) in zip(checks, clips).enumerated() {
                let name = "check\(k).f32"
                try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appendingPathComponent(name))
                entries.append(["audio": name, "runs": runs.map { run in
                    ["words": run.map { index.displayWords[$0] }, "phonemes": run.map { phonemes.words[$0] ?? "" }]
                }])
            }
            try JSONSerialization.data(withJSONObject: ["checks": entries]).write(to: folder.appendingPathComponent("checks.json"))
            print("VOWELS wrote \(folder.path)")
        }
    }

    /// The clip with two words cut out of the audio (الناس at 14.1 s and
    /// كتابه at 35.0 s), streamed live: both are caught, and this prints how
    /// long after the next word was spoken each one shows, and is finalized.
    /// Both clips fed ~10× slower than real time, so each Whisper pass sees
    /// about a second of new audio as on a phone, with the audio's own clock.
    /// Logs every fragment; on the correct clip nothing may show red and then
    /// clear (a false beep), and each cut word is shown. Takes ~40 min.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISPER_E2E_SLOW"] == "1"),
          .timeLimit(.minutes(60)))
    func phonePacedPassesNeverFlashRed() async throws {
        let index = try Self.shatibiyya()
        for name in ["shatibiyya_clip", "shatibiyya_clip_skips"] {
            let clip = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "m4a"))
            let audio = try FileFedAudio(path: clip.path, slowdown: 10)
            let source = WhisperSpeechSource(model: .turbo, audioInput: audio)
            let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
            let start = Task { try await source.start() }
            let drain = Task { () -> [Int: Double] in
                var shownAt: [Int: Double] = [:]
                for await fragment in source.fragments {
                    let now = audio.elapsed
                    tracker.consume(fragment, at: now)
                    print("PACED \(name) \(String(format: "%5.1f", now)) \(fragment.isFinal ? "FINAL   " : "volatile") \(fragment.text)")
                    for (i, o) in tracker.shownOutcomes where o.isMistake && shownAt[i] == nil { shownAt[i] = now }
                }
                return shownAt
            }
            while !audio.finished { try await Task.sleep(for: .milliseconds(500)) }
            try await Task.sleep(for: .seconds(30))
            source.stop()
            let shownAt = await drain.value
            _ = try? await start.value
            let kept = Set(tracker.outcomes.filter { $0.value.isMistake }.keys)
            let flashed = Set(shownAt.keys).subtracting(kept)
            print("PACED \(name) shown \(shownAt.sorted { $0.key < $1.key }.map { "\(index.normalizedWords[$0.key])@\($0.value)" }) flashed \(flashed.sorted().map { index.normalizedWords[$0] })")
            if name == "shatibiyya_clip" { #expect(flashed.isEmpty) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISPER_E2E"] == "1"),
          .timeLimit(.minutes(20)))
    func catchesRealSkipsLive() async throws {
        let clip = try #require(Bundle(for: BundleToken.self).url(forResource: "shatibiyya_clip_skips", withExtension: "m4a"))
        let audio = try FileFedAudio(path: clip.path)
        let source = WhisperSpeechSource(model: .turbo, audioInput: audio)
        let index = try Self.shatibiyya()
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
        // Each cut word, and when (in the cut audio) the word after it starts.
        let targets = [(word: try #require(index.normalizedWords.firstIndex(of: "الناس")), next: 14.12),
                       (word: try #require(index.normalizedWords.firstIndex(of: "كتابه")), next: 34.34)]

        let start = Task { try await source.start() }
        // Times are seconds of audio fed; passes count the recognizer's
        // updates (fragments arriving together are one pass), which carries
        // over to the phone better than Simulator seconds do.
        typealias Seen = (time: Double, pass: Int)
        let drain = Task { () -> [(shown: Seen?, kept: Seen?, nextPass: Int?)] in
            var seen = targets.map { _ in (shown: Seen?.none, kept: Seen?.none, nextPass: Int?.none) }
            var pass = 0
            var lastAt = -1.0
            for await fragment in source.fragments {
                let now = audio.elapsed
                if now != lastAt { pass += 1; lastAt = now }
                tracker.consume(fragment, at: now)
                for (k, target) in targets.enumerated() {
                    if seen[k].nextPass == nil, now >= target.next + 0.6 { seen[k].nextPass = pass }
                    if seen[k].shown == nil, tracker.shownOutcomes[target.word]?.isMistake == true {
                        seen[k].shown = (now, pass)
                    }
                    if seen[k].kept == nil, tracker.outcomes[target.word]?.isMistake == true {
                        seen[k].kept = (now, pass)
                    }
                }
            }
            return seen
        }
        while !audio.finished { try await Task.sleep(for: .milliseconds(200)) }
        try await Task.sleep(for: .seconds(3))
        source.stop()
        let seen = await drain.value
        _ = try? await start.value

        for (target, s) in zip(targets, seen) {
            func after(_ t: Seen?) -> String {
                guard let t else { return "never" }
                let passes = s.nextPass.map { "\(t.pass - $0 + 1) pass(es)" } ?? "?"
                return String(format: "%.1f s / ", t.time - target.next) + passes
            }
            print("SKIP word \(target.word): shown \(after(s.shown)) after the next word, finalized \(after(s.kept))")
            #expect(s.shown != nil)
        }
    }
}

private final class BundleToken {}

/// Keeps the audio of each vowel check, hearing nothing (the Simulator).
private final class ClipRecorder: PhonemeHearing, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [[Float]] = []
    var clips: [[Float]] { lock.withLock { kept } }
    func phonemes(_ samples: [Float]) throws -> String? {
        lock.withLock { kept.append(samples) }
        return nil
    }
}

/// Plays an audio file into WhisperKit as if from the microphone: 100 ms
/// buffers at real-time pace, with the same energy bookkeeping VAD reads.
private final class FileFedAudio: AudioProcessing, @unchecked Sendable {
    private let samples: [Float]
    private let lock = NSLock()
    private var buffer: ContiguousArray<Float> = []
    private var energy: [Float] = []
    private var averages: [Float] = []
    private var feeder: Task<Void, Never>?
    private var done = false
    var relativeEnergyWindow = 20
    /// How many times slower than real time to feed the audio. The Simulator
    /// takes ~10 s a pass, so feeding ~10× slower gives each pass about a
    /// second of new audio, as on a phone.
    private let slowdown: Int

    init(path: String, slowdown: Int = 1) throws {
        samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
        self.slowdown = slowdown
    }

    var finished: Bool { lock.withLock { done } }
    /// Seconds of audio fed so far (the clock of the "recitation").
    var elapsed: Double { lock.withLock { Double(buffer.count) / Double(WhisperKit.sampleRate) } }
    var audioSamples: ContiguousArray<Float> { lock.withLock { buffer } }
    var relativeEnergy: [Float] { lock.withLock { energy } }
    func purgeAudioSamples(keepingLast keep: Int) {}

    func startRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws {
        let step = WhisperKit.sampleRate / 10
        let samples = self.samples
        feeder = Task { [weak self] in
            for at in stride(from: 0, to: samples.count, by: step) {
                guard let self, !Task.isCancelled else { return }
                let chunk = Array(samples[at..<min(samples.count, at + step)])
                self.lock.withLock {
                    let floor = self.averages.suffix(20).min() ?? .infinity
                    self.energy.append(AudioProcessor.calculateRelativeEnergy(of: chunk, relativeTo: floor))
                    self.averages.append(AudioProcessor.calculateEnergy(of: chunk).avg)
                    self.buffer.append(contentsOf: chunk)
                }
                callback?(chunk)
                try? await Task.sleep(for: .milliseconds(100 * self.slowdown))
            }
            self?.lock.withLock { self?.done = true }
        }
    }

    func stopRecording() { feeder?.cancel() }
    func pauseRecording() { feeder?.cancel() }
    func resumeRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws {}
    func startStreamingRecordingLive(inputDeviceID: DeviceID?)
        -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        AsyncThrowingStream.makeStream()
    }

    static func loadAudio(fromPath audioFilePath: String, channelMode: ChannelMode, startTime: Double?,
                          endTime: Double?, maxReadFrameSize: AVAudioFrameCount?) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(fromPath: audioFilePath, channelMode: channelMode, startTime: startTime,
                                     endTime: endTime, maxReadFrameSize: maxReadFrameSize)
    }
    static func loadAudio(at audioPaths: [String], channelMode: ChannelMode) async -> [Result<[Float], Swift.Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }
    static func padOrTrimAudio(fromArray audioArray: [Float], startAt startIndex: Int, toLength frameLength: Int,
                               saveSegment: Bool) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(fromArray: audioArray, startAt: startIndex, toLength: frameLength, saveSegment: saveSegment)
    }
    func padOrTrim(fromArray audioArray: [Float], startAt startIndex: Int, toLength frameLength: Int)
        -> (any AudioProcessorOutputType)? {
        AudioProcessor.padOrTrimAudio(fromArray: audioArray, startAt: startIndex, toLength: frameLength, saveSegment: false)
    }
}
