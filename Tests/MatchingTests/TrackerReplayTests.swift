import Testing
import Foundation
@testable import HifzAlMutun

/// Real recitations' Whisper fragments, captured live with their times by
/// `WhisperTests.aRecordingFromDisk` (`replay_<name>.json`), replayed into
/// the tracker: what the reader would have seen, in milliseconds.
///
/// - `clip`, `skips`: Shatibiyya bayts 1–10 recited correctly, and with two
///   words cut out of the audio.
/// - `r95`, `r96`: a poem's bayt 1, then the *other* poem's bayts 2–3 (the
///   Tuhfa and the Jazariyya both open with يقول راجي).
/// - `r97`: Shatibiyya bayts 1–2, then bayt 4 said in place of bayt 3.
///
/// The `r…` recordings are private: their transcripts are gitignored and
/// kept only where they were captured, so their tests run only there.
@MainActor @Suite struct TrackerReplayTests {
    struct Replay {
        let index: RecitationIndex
        let tracker: RecitationTracker
        /// Every word shown red at some point.
        let everRed: Set<Int>

        /// Kept red at the end.
        var red: Set<Int> { Set(tracker.outcomes.filter { $0.value.isMistake }.keys) }
        /// Shown red, then cleared: a beep taken back.
        var flashed: Set<Int> { everRed.subtracting(red) }
        func words(of bayts: ClosedRange<Int>) -> Set<Int> {
            Set(index.refs.indices.filter { bayts.contains(index.refs[$0].bayt) })
        }
        func describe(_ set: Set<Int>) -> String {
            set.sorted().map { "\(index.refs[$0].bayt):\(index.displayWords[$0])" }.joined(separator: " ")
        }
    }

    /// `asInApp`: the tracker built as the session builds it (bayts, idgham).
    static func replay(_ name: String, asInApp: Bool = false) throws -> Replay {
        struct Fragment: Decodable { let t: Double; let final: Bool; let text: String }
        struct File: Decodable { let matn: String; let fragments: [Fragment] }
        let url = try #require(Bundle(for: ReplayBundleToken.self).url(forResource: "replay_\(name)", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == file.matn })
        let index = RecitationIndex(matn: matn)
        let tracker = asInApp
            ? RecitationTracker(words: index.normalizedWords, startIndex: 0, bayts: index.refs.map(\.bayt),
                                idgham: index.idgham, prose: index.isProse)
            : RecitationTracker(words: index.normalizedWords, startIndex: 0)
        var everRed: Set<Int> = []
        for f in file.fragments {
            tracker.consume(.init(text: f.text, isFinal: f.final), at: f.t)
            everRed.formUnion(tracker.shownOutcomes.filter { $0.value.isMistake }.keys)
        }
        let r = Replay(index: index, tracker: tracker, everRed: everRed)
        print("REPLAY \(name): red [\(r.describe(r.red))] flashed [\(r.describe(r.flashed))] cursor bayt \(r.tracker.cursor < index.refs.count ? index.refs[r.tracker.cursor].bayt : -1)")
        return r
    }

    @Test func aCorrectRecitationStaysQuiet() throws {
        for name in ["clip", "skips"] {
            let r = try Self.replay(name)
            #expect(r.flashed.isEmpty, "\(name)")
            // clip: only كالأترج (heard as كل ترجح). skips: just its two cut
            // words, الناس and كتابه.
            #expect(r.tracker.added.isEmpty, "\(name)")
            if name == "clip" { #expect(r.red.count <= 1) }
            else { #expect(r.describe(r.red) == "2:النَّاسِ 5:كِتَابُهُ") }
        }
    }

    /// Whether a replay's transcript is here (the private ones may not be).
    nonisolated static func has(_ name: String) -> Bool {
        Bundle(for: ReplayBundleToken.self).url(forResource: "replay_\(name)", withExtension: "json") != nil
    }

    @Test(.enabled(if: has("r95") && has("r96")))
    func theOtherPoemsBaytIsAMistake() throws {
        for name in ["r95", "r96"] {
            let r = try Self.replay(name)
            #expect(r.red.isDisjoint(with: r.words(of: 1...1)), "\(name): bayt 1 was right")
            #expect(!r.red.isDisjoint(with: r.words(of: 2...2)), "\(name): bayt 2 was the other poem's")
            #expect(r.flashed.isEmpty, "\(name)")
        }
        // In r95 the words only the other poem has (نبيه ومصطفاه, said between
        // على and محمد) show as added after على.
        let r = try Self.replay("r95")
        #expect(r.tracker.added.mapKeys { r.index.displayWords[$0] } == ["عَلَى": "نبيه ومصطفاه"])
    }

    @Test(.enabled(if: has("r97")))
    func aBaytSaidOutOfOrderIsAMistake() throws {
        let r = try Self.replay("r97")
        #expect(r.red.isDisjoint(with: r.words(of: 2...2)), "bayt 2 was right")
        #expect(!r.red.isDisjoint(with: r.words(of: 3...3)), "bayt 3 was never said")
        #expect(r.flashed.isEmpty)
        // As the app builds it: bayt 3 is one skipped bayt, and bayt 4 is followed.
        let app = try Self.replay("r97", asInApp: true)
        #expect(app.index.skippedBayts(app.tracker.outcomes) == [3])
        #expect(app.red.isDisjoint(with: app.words(of: 4...4)))
    }

    // The `sim_` replays: a computer voice (macOS's Arabic voice) reading the
    // text, through Whisper in the Simulator. Clean speech with no melody, so
    // they show the tracker's logic on real Whisper output, not how well
    // Whisper hears a reciter. `_err`: with mistakes made on purpose.

    @Test func simulatedCorrectReadingsStayQuiet() throws {
        let tuhfa = try Self.replay("sim_tuhfa", asInApp: true)
        #expect(tuhfa.red.isEmpty && tuhfa.flashed.isEmpty)
        // It ends heard as بين معلم for بينمو علما: those two are left unjudged.
        #expect(tuhfa.tracker.outcomes.count == tuhfa.words(of: 1...10).count - 2)
        // ﷺ, said as صلى الله عليه وسلم, is right.
        let hadith = try Self.replay("sim_arbaeen", asInApp: true)
        #expect(hadith.red.isEmpty && hadith.flashed.isEmpty)
        #expect(hadith.tracker.added.isEmpty)
    }

    @Test func simulatedMistakesAreCaught() throws {
        // Bayt 2: لله left out; bayt 4: شيخنا said as كتاب; bayt 6 said
        // twice; bayt 8 left out whole.
        let r = try Self.replay("sim_tuhfa_err", asInApp: true)
        let eight = r.words(of: 8...8)
        #expect(r.describe(r.red.subtracting(eight)) == "2:لِلَّهِ 4:شَيْخِنَا")
        #expect(eight.allSatisfy { r.tracker.outcomes[$0] == .skipped })
        #expect(r.index.skippedBayts(r.tracker.outcomes) == [8])
        #expect(r.index.mistakeCount(r.tracker.outcomes) == 3)
        // Found again at bayt 9, whose first half was heard while lost.
        #expect(r.words(of: 9...9).allSatisfy { r.tracker.outcomes[$0] == .correct || r.tracker.outcomes[$0] == .unsure })
        #expect(r.red.isDisjoint(with: r.words(of: 9...10)))
        // The hadith: الأعمال left out, امرأة said as مال.
        let hadith = try Self.replay("sim_arbaeen_err", asInApp: true)
        #expect(hadith.describe(hadith.red) == "1:الأَعْمالُ 1:امْرَأَةٍ")
    }
}
private final class ReplayBundleToken {}

private extension Dictionary {
    func mapKeys<K: Hashable>(_ f: (Key) -> K) -> [K: Value] {
        Dictionary<K, Value>(uniqueKeysWithValues: map { (f($0.key), $0.value) })
    }
}
