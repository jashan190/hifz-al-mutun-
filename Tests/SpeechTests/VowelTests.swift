import Testing
import Foundation
import AVFoundation
import CoreML
@testable import HifzAlMutun

/// The vowel check: its parts against the Python reference
/// (`Tools/vowels/fixtures.py`), and its judging logic.
@Suite struct VowelTests {
    private static let fatha = VowelJudge.fatha, damma = VowelJudge.damma, kasra = VowelJudge.kasra

    // MARK: - Judging

    @Test func aSwappedVowelIsFoundInItsWord() {
        // بِسْمِ said بِسْمَ, with a little of the next and last words at the edges.
        let slips = VowelJudge.slips(expected: ["بِسمِ", "للَااهِ"], heard: "ءَبِسمَللَااهِفِ")
        #expect(slips == [.init(word: 0, vowel: 1, expected: Self.kasra, heard: Self.fatha)])
    }

    @Test func pausesAndLengthsAreNotSlips() {
        // The last vowel dropped (a pause) and a madd held longer.
        #expect(VowelJudge.slips(expected: ["بِسمِ", "للَااهِ"], heard: "بِسمِللَاااااه").isEmpty)
    }

    @Test func runsAroundAWrongWordAreJudgedApart() {
        // بسم الله | (a wrong word: قال) | الرحمن الرحيم, said الرحَيم;
        // a lone word beside other runs isn't judged.
        let runs = [["بِسمِ", "للَااهِ"], ["ررَحمَاانِ", "ررَحِۦۦمِ"], ["قُل"]]
        let slips = VowelJudge.slips(runs: runs, heard: "بِسمِللَااهِقَالَررَحمَاانِررَحَۦۦمِقَل")
        #expect(slips == [[], [.init(word: 1, vowel: 1, expected: Self.kasra, heard: Self.fatha)], []])
    }

    @Test func theSlipIsWrittenOnItsLetter() {
        #expect(VowelJudge.written("الْحَمْدُ", phonemes: "لحَمدُ", vowel: 1, heard: Self.fatha) == "الْحَمْدَ")
        #expect(VowelJudge.written("كِتَابُهُ", phonemes: "كِتَاابُهُۥ", vowel: 0, heard: Self.fatha) == "كَتَابُهُ")
        // A tanween stays a tanween.
        #expect(VowelJudge.written("أَحَدٌ", phonemes: "ءَحَدُن", vowel: 2, heard: Self.kasra) == "أَحَدٍ")
        // اللهِ: the lam's fatha isn't written, so the slip can't be placed.
        #expect(VowelJudge.written("اللهِ", phonemes: "للَااهِ", vowel: 1, heard: Self.fatha) == nil)
    }

    @Test func theChangedVowelIsMarked() {
        let word = "الْحَمْدُ"
        let scalars = Array(word.unicodeScalars).map { String($0) }
        let marked = LetterEmphasis.ranges(written: word, heard: "الْحَمْدَ")
        #expect(marked.map { scalars[$0].joined() } == ["دُ"])
    }

    @Test func aVowelSlipMakesACorrectWordWrong() {
        let tracker = RecitationTracker(words: ["بدات", "بسم", "الله"])
        tracker.consume(.init(text: "بدات بسم الله", isFinal: true), at: 0)
        tracker.markVowelSlip(1, said: "بِسْمَ", generation: tracker.generation)
        #expect(tracker.outcomes[1] == .wrong(heard: "بِسْمَ"))
        #expect(tracker.heard[1] == "بِسْمَ")
        tracker.override(1, with: .correct)              // "Not a mistake"
        #expect(tracker.outcomes[1] == .correct)
        tracker.markVowelSlip(5, said: "x", generation: tracker.generation)   // never judged: ignored
        #expect(tracker.outcomes[5] == nil)
    }

    @Test func aVowelCheckFromBeforeAJumpIsIgnored() {
        let tracker = RecitationTracker(words: ["بدات", "بسم", "الله"])
        tracker.consume(.init(text: "بدات بسم الله", isFinal: true), at: 0)
        let before = tracker.generation                  // a check starts on this recitation…
        tracker.jump(to: 0, at: 1)                       // …the reciter starts again…
        tracker.consume(.init(text: "بدات بسم الله", isFinal: true), at: 2)
        tracker.markVowelSlip(1, said: "بِسْمَ", generation: before)   // …and its result lands late
        #expect(tracker.outcomes[1] == .correct)
    }

    @MainActor @Test func everyMatnHasItsPhonemes() {
        let store = ContentStore()
        store.load()
        // Phoneme coverage is a voice (recitation) check and is opt-in per matn: a
        // poem ships a phoneme file only once its references are generated with
        // Tools/vowels/build_phonemes.py. Prose matns have no bayt-words, so
        // they're out of scope; poems without a phoneme file yet (e.g.
        // al-Bayquniyyah, al-Urjuza al-Mi'iyya) are skipped. Any poem that DOES
        // ship phonemes must still cover > 95% of its words.
        for matn in store.matns where matn.kind == .poem {
            let index = RecitationIndex(matn: matn)
            guard let phonemes = PhonemeIndex(matnID: matn.id, index: index) else { continue }
            #expect(phonemes.words.count == index.normalizedWords.count)
            let known = phonemes.words.compactMap { $0 }.count
            #expect(Double(known) / Double(phonemes.words.count) > 0.95, "\(matn.id): \(known)")
        }
    }

    // MARK: - Against Python

    @Test func featuresMatchPython() throws {
        let samples = try Self.clip()
        let window = try Self.windows()[0]
        let (mine, count) = PhonemeFeatures.frames(Array(samples[window.from..<window.to]))
        let theirs = try Self.floats("vowel_window0")
        #expect(mine.count == theirs.count)
        #expect(count * PhonemeFeatures.width == mine.count)
        let diffs = zip(mine, theirs).map { abs($0 - $1) }
        let worst = diffs.max() ?? .infinity, mean = diffs.reduce(0, +) / Float(diffs.count)
        print("VOWEL features: \(count) frames, largest difference \(worst), mean \(mean)")
        #expect(worst < 0.01)
    }

    /// Swift features → the Core ML model → greedy decoding hear the same
    /// vowels as Python, window by window (padding a clip to the model's
    /// fixed lengths can change other phonemes a little), and the clip (a
    /// correct recitation of bayts 1–10) shows almost no slips. Needs the
    /// exported model: TEST_RUNNER_VOWEL_MODEL=/path/to/Muaalem_int8.mlpackage,
    /// and a Mac or phone destination. (`Tools/vowels/swift` runs the same
    /// comparison on the Mac from the command line.)
    @Test(.enabled(if: VowelTests.canRunModel), .timeLimit(.minutes(10)))
    @MainActor func hearsWhatPythonHears() async throws {
        let model = try PhonemeModel(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOWEL_MODEL"]!))
        let samples = try Self.clip()
        var same = 0, swaps = 0, heard = ""
        let windows = try Self.windows()
        for w in windows {
            let start = Date()
            let mine = try #require(try model.phonemes(Array(samples[w.from..<w.to])))
            print("VOWEL window \(w.from / 16): \(Int(Date().timeIntervalSince(start) * 1000)) ms\(mine == w.phonemes ? "" : "\n  swift  \(mine)\n  python \(w.phonemes)")")
            same += mine == w.phonemes ? 1 : 0
            swaps += VowelJudge.slips(expected: [w.phonemes], heard: mine).count
            heard += mine
        }
        print("VOWEL identical on \(same)/\(windows.count) windows, \(swaps) vowels heard differently")
        #expect(swaps == 0)

        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == "shatibiyya" })
        let index = RecitationIndex(matn: matn)
        let phonemes = try #require(PhonemeIndex(matnID: matn.id, index: index))
        let words = index.refs.indices.filter { (1...10).contains(index.refs[$0].bayt) }
        let slips = VowelJudge.slips(expected: words.map { phonemes.words[$0] ?? "" }, heard: heard)
        print("VOWEL slips on the correct clip: \(slips.map { index.displayWords[words[$0.word]] })")
        #expect(slips.count <= 2)
    }

    /// The model runs on a Mac or a phone, not in the Simulator (its Core ML
    /// segfaults, taking the test runner down), and only with a path to it.
    static var canRunModel: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ProcessInfo.processInfo.environment["VOWEL_MODEL"] != nil
        #endif
    }

    // MARK: - Fixtures

    private struct Window: Decodable { let from: Int; let to: Int; let phonemes: String }

    private static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle(for: VowelBundleToken.self).url(forResource: name, withExtension: ext))
    }

    private static func windows() throws -> [Window] {
        struct File: Decodable { let windows: [Window] }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url("vowel_windows", "json"))).windows
    }

    private static func floats(_ name: String) throws -> [Float] {
        let data = try Data(contentsOf: url(name, "f32"))
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// The clip at 16 kHz, as Python read it.
    private static func clip() throws -> [Float] {
        let file = try AVAudioFile(forReading: url("shatibiyya_clip_16k", "flac"))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
private final class VowelBundleToken {}
