import Foundation
import MLXLLM
import MLXLMCommon

let task = Task {
    print("=== Cogito LLM Speed Benchmark ===\n")

    let config = LLMRegistry.gemma3n_E4B_it_lm_4bit
    print("Model : \(config.name)")
    print("Device: Apple Silicon (MLX Metal)\n")

    // Load model
    print("Loading model...")
    let container: ModelContainer
    do {
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { _ in }
        print("Model loaded.\n")
    } catch {
        print("Failed: \(error)")
        return
    }

    // Benchmark helper
    func bench(label: String, prompt: String, maxTokens: Int, systemPrompt: String? = nil) async {
        let params = GenerateParameters(maxTokens: maxTokens)
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )

        print("[\(label)]")
        print("  Prompt (\(prompt.count) chars): \"\(prompt.prefix(60))\(prompt.count > 60 ? "..." : "")\"")
        print("  Response: ", terminator: "")
        fflush(stdout)

        var info: GenerateCompletionInfo?
        do {
            for try await event in session.streamDetails(to: prompt, images: [], videos: []) {
                switch event {
                case .chunk(let text):
                    print(text, terminator: "")
                    fflush(stdout)
                case .info(let i):
                    info = i
                case .toolCall:
                    break
                }
            }
        } catch {
            print("\n  Error: \(error)")
            return
        }
        print("\n")

        if let i = info {
            print("  Prompt : \(i.promptTokenCount) tokens  |  \(String(format: "%.1f", i.promptTokensPerSecond)) tok/s  |  \(String(format: "%.2f", i.promptTime))s")
            print("  Generate: \(i.generationTokenCount) tokens  |  \(String(format: "%.1f", i.tokensPerSecond)) tok/s  |  \(String(format: "%.2f", i.generateTime))s")
            print("  Stop: \(i.stopReason)\n")
        }
    }

    await bench(
        label: "ELI12: What is a perceptron?",
        prompt: "Explain to me like I'm 12: What is perceptron?",
        maxTokens: 2048
    )
}

_ = await task.value
