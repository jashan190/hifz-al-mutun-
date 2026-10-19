// Replays captured Whisper fragments (Tests/SpeechTests/Fixtures/replay_*.json,
// written by `WhisperTests.aRecordingFromDisk`) into the tracker on the Mac,
// in a second instead of an Xcode test run, and prints what showed red.
//
//   swiftc -O -o /tmp/replay Core/Models/{Matn,LegacyMatn}.swift Core/Matching/*.swift Tools/replay/main.swift
//   /tmp/replay Tests/SpeechTests/Fixtures Resources/Content
import Foundation

struct Fragment: Decodable { let t: Double; let final: Bool; let text: String }
struct File: Decodable { let matn: String; let fragments: [Fragment] }

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
let content = URL(fileURLWithPath: CommandLine.arguments[2])
for name in ["clip", "skips", "r95", "r96", "r97"] {
    // The r… recordings are private (gitignored): replayed only where present.
    guard let data = try? Data(contentsOf: fixtures.appendingPathComponent("replay_\(name).json")) else { continue }
    let file = try JSONDecoder().decode(File.self, from: data)
    let matn = try JSONDecoder().decode(Matn.self, from: Data(contentsOf: content.appendingPathComponent("\(file.matn).json")))
    let index = RecitationIndex(matn: matn)
    let tracker = RecitationTracker(words: index.normalizedWords, startIndex: 0)
    var everRed: Set<Int> = []
    var everAdded: Set<Int> = []
    for f in file.fragments {
        tracker.consume(.init(text: f.text, isFinal: f.final), at: f.t)
        for (k, v) in tracker.added where !everAdded.contains(k) {
            everAdded.insert(k)
            print(String(format: "  %@ %5.1f s %@  ADDED after %@: %@", name, f.t, f.final ? "FINAL" : "guess", index.displayWords[k], v))
        }
        let red = tracker.shownOutcomes.filter { $0.value.isMistake }.keys
        let new = Set(red).subtracting(everRed)
        if !new.isEmpty {
            let words = new.sorted().map { "\(index.refs[$0].bayt):\(index.displayWords[$0])" }.joined(separator: " ")
            print("  \(name) \(String(format: "%5.1f", f.t)) s \(f.final ? "FINAL" : "guess")  RED \(words)  «\(f.text)»")
        }
        everRed.formUnion(red)
    }
    let flashedAdded = everAdded.subtracting(tracker.added.keys)
    if !flashedAdded.isEmpty { print("  \(name) ADDED THEN CLEARED: \(flashedAdded.map { index.displayWords[$0] })") }
    let red = Set(tracker.outcomes.filter { $0.value.isMistake }.keys)
    func show(_ s: Set<Int>) -> String {
        s.sorted().map { i -> String in
            let heard: String
            if case .wrong(let h)? = tracker.outcomes[i] { heard = "(\(h))" } else { heard = "" }
            return "\(index.refs[i].bayt):\(index.displayWords[i])\(heard)"
        }.joined(separator: " ")
    }
    let added = tracker.added.sorted { $0.key < $1.key }.map { "after \(index.refs[$0.key].bayt):\(index.displayWords[$0.key]) + \($0.value)" }
    print("\(name): red [\(show(red))] flashed [\(show(everRed.subtracting(red)))] added \(added)")
}
