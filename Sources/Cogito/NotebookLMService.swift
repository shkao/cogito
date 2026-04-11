import Foundation

// MARK: - VideoStatus

enum VideoStatus: Sendable {
    case uploading(message: String)
    case generating(elapsedSeconds: Int)
    case downloading
    case done(videoPath: URL)
    case authRequired
    case error(String)

    var statusText: String {
        switch self {
        case .uploading(let msg): return msg
        case .generating(let s):
            return String(format: "Generating... (%d:%02d)", s / 60, s % 60)
        case .downloading: return "Downloading video..."
        case .done: return "Video ready"
        case .authRequired: return "Login required"
        case .error(let msg): return msg
        }
    }

    var isTerminal: Bool {
        switch self { case .done, .authRequired, .error: return true; default: return false }
    }
    var isDone: Bool { if case .done = self { return true }; return false }
    var isAuthRequired: Bool { if case .authRequired = self { return true }; return false }
    var isError: Bool { if case .error = self { return true }; return false }
}

// MARK: - Video format/style preferences

enum VideoFormat: String, CaseIterable, Identifiable {
    case explainer
    case deepDive = "deep_dive"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .explainer: return "Explainer"
        case .deepDive: return "Deep Dive"
        }
    }
}

enum VideoStyle: String, CaseIterable, Identifiable {
    case whiteboard
    case slideshow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .whiteboard: return "Whiteboard"
        case .slideshow: return "Slideshow"
        }
    }
}

// MARK: - NotebookLMService

actor NotebookLMService {
    private var activeProcesses: [String: Process] = [:]
    private static let authKeywords = ["auth", "login", "cookie", "credential", "unauthenticated", "permission", "403", "sign in"]

    func generateVideo(
        pdfPath: URL,
        outputPath: URL,
        title: String,
        format: VideoFormat = .explainer,
        style: VideoStyle = .whiteboard
    ) -> AsyncStream<VideoStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: VideoStatus.self)
        Task { await runProcess(pdfPath: pdfPath, outputPath: outputPath, title: title, format: format, style: style, continuation: continuation) }
        return stream
    }

    func cancel(title: String) {
        activeProcesses[title]?.terminate()
        activeProcesses[title] = nil
    }

    // MARK: - Private

    private func runProcess(
        pdfPath: URL,
        outputPath: URL,
        title: String,
        format: VideoFormat,
        style: VideoStyle,
        continuation: AsyncStream<VideoStatus>.Continuation
    ) async {
        guard let scriptPath = Self.resolveScriptPath() else {
            continuation.yield(.error("generate_video.py not found. Rebuild the app."))
            continuation.finish()
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "python3", scriptPath,
            "--pdf-path", pdfPath.path,
            "--output-path", outputPath.path,
            "--title", title,
            "--format", format.rawValue,
            "--style", style.rawValue,
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        activeProcesses[title] = proc

        do {
            try proc.run()
        } catch {
            continuation.yield(.error("Failed to launch Python: \(error.localizedDescription)"))
            continuation.finish()
            return
        }

        var hadTerminalStatus = false
        do {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { proc.terminate(); break }
                if let data = line.data(using: .utf8), let status = Self.parse(data) {
                    continuation.yield(status)
                    if status.isTerminal { hadTerminalStatus = true; break }
                }
            }
        } catch {
            continuation.yield(.error("Stream error: \(error.localizedDescription)"))
            hadTerminalStatus = true
        }

        // If the process exited without emitting a terminal status (e.g. Python
        // crashed before printing any JSON), surface stderr as the error message.
        if !hadTerminalStatus {
            proc.waitUntilExit()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = (String(data: stderrData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = stderrText.isEmpty
                ? "Process exited with code \(proc.terminationStatus)"
                : stderrText
            continuation.yield(.error(msg))
        }

        continuation.finish()
    }

    private static func parse(_ data: Data) -> VideoStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else { return nil }
        switch status {
        case "uploading", "generating":
            let msg = json["message"] as? String ?? "Working..."
            return .uploading(message: msg)
        case "polling":
            let elapsed = json["elapsed"] as? Int ?? 0
            return .generating(elapsedSeconds: elapsed)
        case "downloading":
            return .downloading
        case "done":
            guard let path = json["path"] as? String else { return nil }
            return .done(videoPath: URL(fileURLWithPath: path))
        case "error":
            let msg = json["message"] as? String ?? "Unknown error"
            let lower = msg.lowercased()
            if Self.authKeywords.contains(where: { lower.contains($0) }) {
                return .authRequired
            }
            return .error(msg)
        default:
            return nil
        }
    }

    private static func resolveScriptPath() -> String? {
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).resolvingSymlinksInPath()

        // Bundled app: Contents/MacOS/Cogito -> Contents/Resources/Scripts/
        let bundled = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Scripts/generate_video.py")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }

        // Dev build: .build/arch/config/Cogito -> repo root Scripts/
        let dev = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/generate_video.py")
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev.path
        }

        return nil
    }
}
