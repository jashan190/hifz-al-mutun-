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

    static func replay(_ name: String) throws -> Replay {
        struct Fragment: Decodable { let t: Double; let final: Bool; let text: String }
        struct File: Decodable { let matn: String; let fragments: [Fragment] }
        let url = try #require(Bundle(for: ReplayBundleToken.self).url(forResource: "replay_\(name)", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let store = ContentStore()
        store.load()
        let matn = try #require(store.matns.first { $0.id == file.matn })
        let index = RecitationIndex(matn: matn)
        let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
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
            // As before this suite. clip: رحيماً (Whisper writes الرحيم) and
            // كالأترج (heard as كل ترجح). skips: رحيماً, its two cut words, and
            // مرسلا (heard joined to الناس).
            #expect(r.red.count <= (name == "clip" ? 2 : 4), "\(name)")
        }
    }

    @Test func theOtherPoemsBaytIsAMistake() throws {
        for name in ["r95", "r96"] {
            let r = try Self.replay(name)
            #expect(r.red.isDisjoint(with: r.words(of: 1...1)), "\(name): bayt 1 was right")
            #expect(!r.red.isDisjoint(with: r.words(of: 2...2)), "\(name): bayt 2 was the other poem's")
            #expect(r.flashed.isEmpty, "\(name)")
        }
    }

    @Test func aBaytSaidOutOfOrderIsAMistake() throws {
        let r = try Self.replay("r97")
        #expect(r.red.isDisjoint(with: r.words(of: 2...2)), "bayt 2 was right")
        #expect(!r.red.isDisjoint(with: r.words(of: 3...3)), "bayt 3 was never said")
        #expect(r.flashed.isEmpty)
    }
}
private final class ReplayBundleToken {}
