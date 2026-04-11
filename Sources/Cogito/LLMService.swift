import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - LLMService

/// Thread-safe, singleton LLM engine. Loads Gemma 3n E4B (4-bit) locally
/// via MLX on Apple Silicon. All state transitions run on this actor.
actor LLMService {
    static let shared = LLMService()

    enum State: Sendable {
        case idle
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    private(set) var state: State = .idle
    private var container: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?

    private static let configuration = LLMRegistry.gemma3n_E4B_it_lm_4bit

    private init() {}

    // MARK: Model Lifecycle

    /// Load the model, downloading from HuggingFace if not cached (~2-3 GB, one-time).
    /// Safe to call multiple times; concurrent callers share the same in-flight download.
    @discardableResult
    func loadModel(onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws -> ModelContainer {
        if let c = container { return c }
        if let t = loadingTask { return try await t.value }

        state = .downloading(progress: 0)

        let task = Task<ModelContainer, Error> {
            try await LLMModelFactory.shared.loadContainer(
                configuration: Self.configuration
            ) { [weak self] progress in
                let fraction = progress.fractionCompleted
                onProgress(fraction)
                if fraction < 1.0 {
                    Task { [weak self] in await self?.setDownloadState(fraction) }
                }
            }
        }
        loadingTask = task

        do {
            let loaded = try await task.value
            container = loaded
            loadingTask = nil
            state = .ready
            return loaded
        } catch {
            container = nil
            loadingTask = nil
            state = .error(error.localizedDescription)
            throw error
        }
    }

    private func setDownloadState(_ fraction: Double) {
        state = .downloading(progress: fraction)
    }

    /// Release the model from memory (~2-3 GB). The next `generate` call will reload it.
    func unloadModel() {
        container = nil
        loadingTask = nil
        state = .idle
    }

    // MARK: Generation

    /// Stream generated text token by token. Loads the model on demand if not ready.
    /// Cancel the consuming Task to stop generation immediately.
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 512
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [self] continuation in
            Task {
                do {
                    let c = if let existing = self.container { existing } else { try await self.loadModel() }
                    let session = ChatSession(
                        c,
                        instructions: systemPrompt,
                        generateParameters: GenerateParameters(maxTokens: maxTokens)
                    )
                    for try await chunk in session.streamResponse(to: prompt) {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
