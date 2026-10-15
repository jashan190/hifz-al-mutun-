import Foundation
import WhisperKit

/// Holds the loaded Whisper model for the whole app run, so each sitting
/// (a mic tap, "Review again", a bayt tap) reuses it instead of loading
/// 632 MB again. Also keeps a single download in flight: WhisperKit's
/// downloader doesn't stop when its task is cancelled, so a mic turned off
/// mid-download lets that download finish, and the next start waits for it
/// rather than starting a second one into the same folder.
actor WhisperEngine {
    static let shared = WhisperEngine()

    private var loaded: (model: WhisperModel, whisper: WhisperKit)?
    private var pending: (model: WhisperModel, task: Task<WhisperKit, Error>)?
    // The latest caller's progress handlers (an earlier caller may have gone).
    private var onProgress: (@Sendable (Double) -> Void)?
    private var onLoading: (@Sendable () -> Void)?

    /// The loaded model, downloading and loading it first if needed.
    func whisper(for model: WhisperModel,
                 progress: @escaping @Sendable (Double) -> Void,
                 loading: @escaping @Sendable () -> Void) async throws -> WhisperKit {
        if let loaded, loaded.model == model { return loaded.whisper }
        onProgress = progress
        onLoading = loading
        let task: Task<WhisperKit, Error>
        if let pending, pending.model == model {
            task = pending.task
        } else {
            task = Task { try await self.make(model) }
            pending = (model, task)
        }
        do {
            let whisper = try await task.value
            if pending?.model == model { pending = nil }
            loaded = (model, whisper)
            return whisper
        } catch {
            if pending?.model == model { pending = nil }
            throw error
        }
    }

    /// Drop a model removed in Settings.
    func forget(_ model: WhisperModel) {
        if loaded?.model == model { loaded = nil }
    }

    private func make(_ model: WhisperModel) async throws -> WhisperKit {
        try await model.download { [weak self] p in
            Task { await self?.reportProgress(p) }
        }
        onLoading?()
        let config = WhisperKitConfig(
            modelFolder: model.folder.path,
            tokenizerFolder: WhisperModel.storage,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        do {
            return try await WhisperKit(config)
        } catch {
            // Most likely the tokenizer, fetched on the first load.
            throw SpeechSourceError.modelDownloadFailed
        }
    }

    private func reportProgress(_ p: Double) { onProgress?(p) }
}
