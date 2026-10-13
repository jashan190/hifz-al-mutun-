import Foundation
import SwiftData

/// A word marked for review (UX.md "flags"). Keyed by position, not text, so
/// re-building a matn's JSON never orphans a user's flags.
@Model
final class WordFlag {
    var matnID: String
    var bayt: Int
    var half: String          // "sadr" | "ajuz"
    var wordIndex: Int
    var createdAt: Date

    init(matnID: String, bayt: Int, half: Half, wordIndex: Int, createdAt: Date = .now) {
        self.matnID = matnID
        self.bayt = bayt
        self.half = half.storageKey
        self.wordIndex = wordIndex
        self.createdAt = createdAt
    }
}

extension Half {
    var storageKey: String { self == .sadr ? "sadr" : "ajuz" }
    init?(storageKey: String) {
        switch storageKey {
        case "sadr": self = .sadr
        case "ajuz": self = .ajuz
        default: return nil
        }
    }
}

/// One flagged word's position within a matn.
struct FlagKey: Hashable {
    let bayt: Int
    let half: Half
    let wordIndex: Int
}

/// Reads and writes flags. Keeps the flags of every matn in memory as sets
/// (a matn has at most a few thousand words), so the page can ask "is this
/// word flagged?" while rendering.
@MainActor
final class FlagStore: ObservableObject {
    @Published private(set) var flags: [String: Set<FlagKey>] = [:]
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<WordFlag>())) ?? []
        for f in all {
            guard let half = Half(storageKey: f.half) else { continue }
            flags[f.matnID, default: []].insert(FlagKey(bayt: f.bayt, half: half, wordIndex: f.wordIndex))
        }
    }

    /// A store backed by memory only, for previews and tests.
    static func inMemory() -> FlagStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return FlagStore(container: try! ModelContainer(for: WordFlag.self, configurations: config))
    }

    func isFlagged(_ matnID: String, _ key: FlagKey) -> Bool {
        flags[matnID]?.contains(key) ?? false
    }

    func setFlag(_ on: Bool, matnID: String, _ key: FlagKey) {
        guard on != isFlagged(matnID, key) else { return }
        if on {
            flags[matnID, default: []].insert(key)
            context.insert(WordFlag(matnID: matnID, bayt: key.bayt, half: key.half, wordIndex: key.wordIndex))
        } else {
            flags[matnID]?.remove(key)
            let half = key.half.storageKey, bayt = key.bayt, word = key.wordIndex
            let match = FetchDescriptor<WordFlag>(predicate: #Predicate {
                $0.matnID == matnID && $0.bayt == bayt && $0.half == half && $0.wordIndex == word
            })
            for f in (try? context.fetch(match)) ?? [] { context.delete(f) }
        }
        try? context.save()
    }

    func count(for matnID: String) -> Int { flags[matnID]?.count ?? 0 }

    /// Remove every flag (e.g. after test runs that flagged words wrongly).
    func clearAll() {
        flags = [:]
        try? context.delete(model: WordFlag.self)
        try? context.save()
    }
}
