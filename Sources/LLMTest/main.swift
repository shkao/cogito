import Foundation
import HFAPI
import MLXBridge
import MLXLLM
import MLXLMCommon

let task = Task {
    print("=== Cogito LLM Speed Benchmark ===\n")

    let config = LLMRegistry.gemma4_e4b_it_4bit
    print("Model : \(config.name)")
    print("Device: Apple Silicon (MLX Metal)\n")

    print("Loading model...")
    let container: ModelContainer
    do {
        container = try await LLMModelFactory.shared.loadContainer(
            from: HubClient.default,
            using: TokenizersLoader(),
            configuration: config
        ) { _ in }
        print("Model loaded.\n")
    } catch {
        print("Failed: \(error)")
        return
    }

    func bench(label: String, prompt: String, maxTokens: Int, systemPrompt: String? = nil) async {
        let params = GenerateParameters(maxTokens: maxTokens)
        let session = ChatSession(container, instructions: systemPrompt, generateParameters: params)

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
            let promptTPS = String(format: "%.1f", i.promptTokensPerSecond)
            let promptT = String(format: "%.2f", i.promptTime)
            print("  Prompt : \(i.promptTokenCount) tokens  |  \(promptTPS) tok/s  |  \(promptT)s")
            let genTPS = String(format: "%.1f", i.tokensPerSecond)
            let genT = String(format: "%.2f", i.generateTime)
            print("  Generate: \(i.generationTokenCount) tokens  |  \(genTPS) tok/s  |  \(genT)s")
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
