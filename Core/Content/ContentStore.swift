import Foundation

// Loads the read-only matn JSON files that are bundled with the app.
//
// For now this discovers every "*.json" in the bundle that decodes as a Matn.
// As we add al-Jazariyyah and ash-Shatibiyyah, dropping their JSON into
// Resources/Content is all that's needed — no code change here.

@MainActor
final class ContentStore: ObservableObject {
    @Published private(set) var matns: [Matn] = []
    @Published private(set) var loadError: String?

    init() {
        load()
    }

    func load() {
        do {
            matns = try Self.loadAll()
            loadError = matns.isEmpty ? "No matn content found in the app bundle." : nil
            logReviewNotes()
        } catch {
            matns = []
            loadError = "Failed to load content: \(error)"
        }
    }

    /// The transcriber's open spots are never shown in the app. In debug builds
    /// we print them so they can be checked against the book.
    private func logReviewNotes() {
        #if DEBUG
        for matn in matns where !matn.reviewNotes.isEmpty {
            print("── review notes: \(matn.id) (\(matn.reviewNotes.count)) ──")
            for note in matn.reviewNotes {
                print("  p\(note.page) bayt \(note.n): \(note.notes.joined(separator: " | "))")
            }
        }
        #endif
    }

    /// Find a loaded matn by its id (e.g. "tuhfa").
    func matn(id: String) -> Matn? {
        matns.first { $0.id == id }
    }

    // MARK: - Loading

    private static func loadAll() throws -> [Matn] {
        let decoder = JSONDecoder()
        // Content JSON lives in Resources/Content, which is flattened into the
        // bundle. Decode any top-level JSON that looks like a Matn.
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json",
                                          subdirectory: nil) else {
            return []
        }

        var result: [Matn] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            // Only treat files that decode as a Matn as content; skip anything else.
            if let matn = try? decoder.decode(Matn.self, from: data) {
                result.append(matn)
            }
        }
        // Stable order: shortest first (Tuhfa, Jazariyyah, Shatibiyyah).
        return result.sorted { $0.baytCount < $1.baytCount }
    }
}
