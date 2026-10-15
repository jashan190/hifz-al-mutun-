import Foundation
import WhisperKit

/// The Whisper model voice review listens with. Downloaded once from
/// Hugging Face (argmaxinc/whisperkit-coreml), then runs on the phone.
///
/// On the bundled Shatibiyyah clip (80 s, bayts 1–10) Turbo got 13% of words
/// wrong and Small 36%, so Turbo is the default; Small is for older phones.
enum WhisperModel: String, CaseIterable, Identifiable {
    case turbo
    case small

    var id: String { rawValue }

    /// The folder name in the model repo.
    var variant: String {
        switch self {
        case .turbo: return "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .small: return "openai_whisper-small_216MB"
        }
    }

    var title: String {
        switch self {
        case .turbo: return "Whisper Turbo"
        case .small: return "Whisper Small"
        }
    }

    var detail: String {
        switch self {
        case .turbo: return "Most accurate · 632 MB"
        case .small: return "For older iPhones · 216 MB"
        }
    }

    static let defaultsKey = "whisperModel"

    /// The model chosen in Settings.
    static var selected: WhisperModel {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(WhisperModel.init) ?? .turbo
    }

    // MARK: - Storage

    /// Models and the tokenizer live in Application Support, which isn't
    /// shown in Files; it is excluded from iCloud backup (it can be fetched again).
    static var storage: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Whisper", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            var url = base
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return base
    }

    /// Where WhisperKit's downloader puts this model.
    var folder: URL {
        Self.storage.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory)
    }

    /// Written once a download finishes, so a half-finished one isn't loaded.
    private var marker: URL { folder.appending(path: ".complete") }

    var isDownloaded: Bool { FileManager.default.fileExists(atPath: marker.path) }

    /// Fetch the model if it isn't here yet, reporting progress 0…1.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isDownloaded else { return }
        do {
            let url = try await WhisperKit.download(variant: variant, downloadBase: Self.storage) {
                progress($0.fractionCompleted)
            }
            assert(url.standardizedFileURL.path == folder.standardizedFileURL.path,
                   "WhisperKit stored the model at \(url.path)")
            try Data().write(to: marker)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechSourceError.modelDownloadFailed
        }
    }

    /// Free the space (Settings).
    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
