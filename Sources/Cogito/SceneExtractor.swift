import AppKit
import Foundation

struct SceneFrame: Identifiable {
    let id = UUID()
    let time: Double
    let image: NSImage
}

/// Extracts scene-change frames from a video using ffmpeg scene detection
/// with perceptual hash deduplication, mirroring the pipeline in mooc/extract-slides.
///
/// Pipeline: ffmpeg scene detect -> parse pts_time -> rename to MM_SS.jpg -> pHash dedup -> cache
/// Fallback: fixed-interval extraction every 30s when scene detection yields 0 frames.
actor SceneExtractor {
    static let shared = SceneExtractor()

    private let cacheDir: URL = {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = caches.appendingPathComponent(
            "com.cogito.app/Scenes", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }()

    private let sceneThreshold = 0.3
    private let dedupThreshold = 5 // hamming distance, out of 64 bits

    // MARK: - Public

    func extractScenes(from videoURL: URL) async -> [SceneFrame] {
        let cacheKey = videoURL.deletingPathExtension().lastPathComponent
        let metaURL = cacheDir.appendingPathComponent("\(cacheKey).json")
        let thumbDir = cacheDir.appendingPathComponent(
            cacheKey, isDirectory: true
        )

        if let cached = loadCached(metaURL: metaURL, thumbDir: thumbDir) {
            return cached
        }

        try? FileManager.default.createDirectory(
            at: thumbDir, withIntermediateDirectories: true
        )

        // Step 1: ffmpeg scene detection
        let stderr = await runSceneDetect(
            videoPath: videoURL.path, outDir: thumbDir.path
        )

        let frameFiles = jpgFiles(in: thumbDir, prefix: "frame_")

        if !frameFiles.isEmpty {
            let timestamps = parseShowinfoTimestamps(
                stderr, count: frameFiles.count
            )
            renameWithTimestamps(
                dir: thumbDir, files: frameFiles, timestamps: timestamps
            )
        }

        // Check what we have after rename
        var allJpgs = jpgFiles(in: thumbDir)

        // Fallback: fixed interval if scene detection found nothing
        if allJpgs.isEmpty {
            await extractFixedFrames(
                videoPath: videoURL.path, outDir: thumbDir.path
            )
            allJpgs = jpgFiles(in: thumbDir)
        }

        guard !allJpgs.isEmpty else { return [] }

        // Step 2: pHash dedup
        deduplicateFrames(in: thumbDir, files: allJpgs)

        // Step 3: Build result from surviving files
        let finalFiles = jpgFiles(in: thumbDir)
        var entries: [[String: Any]] = []
        var result: [SceneFrame] = []

        for file in finalFiles {
            let time = parseTimestamp(from: file)
            let url = thumbDir.appendingPathComponent(file)
            guard let image = NSImage(contentsOf: url) else { continue }
            entries.append(["time": time, "file": file])
            result.append(SceneFrame(time: Double(time), image: image))
        }

        if let json = try? JSONSerialization.data(
            withJSONObject: entries, options: .prettyPrinted
        ) {
            try? json.write(to: metaURL)
        }

        return result
    }

    // MARK: - ffmpeg scene detection

    /// Runs `ffmpeg -vf select='gt(scene,T)',showinfo` and returns stderr
    /// (which contains pts_time entries from showinfo).
    private func runSceneDetect(videoPath: String, outDir: String) async -> String {
        let prefix = (outDir as NSString).appendingPathComponent(
            "frame_%04d.jpg"
        )
        let vf = "select='gt(scene\\,\(sceneThreshold))',showinfo"
        let args = [
            "-y", "-i", videoPath,
            "-vf", vf,
            "-vsync", "vfn",
            "-q:v", "3",
            prefix,
        ]
        return await runFFmpeg(args)
    }

    // MARK: - Fixed interval fallback

    private func extractFixedFrames(videoPath: String, outDir: String) async {
        let duration = await videoDuration(videoPath)
        guard duration > 0 else { return }

        let interval = 30.0
        var times: [Double] = [1]
        var t = interval
        while t < duration - 5 {
            times.append(t)
            t += interval
        }
        let nearEnd = duration - 3
        if duration > 10, nearEnd > (times.last ?? 0) + 5 {
            times.append(nearEnd)
        }

        for sec in times {
            let mm = Int(sec) / 60
            let ss = Int(sec) % 60
            let filename = String(
                format: "%02d_%02d.jpg", mm, ss
            )
            let outPath = (outDir as NSString).appendingPathComponent(
                filename
            )
            let args = [
                "-y", "-ss", String(sec),
                "-i", videoPath,
                "-frames:v", "1", "-q:v", "3",
                outPath,
            ]
            _ = await runFFmpeg(args)
        }
    }

    private func videoDuration(_ path: String) async -> Double {
        await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [
                "ffprobe", "-v", "quiet",
                "-show_entries", "format=duration",
                "-of", "csv=p=0", path,
            ]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let str = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Double(str) ?? 0
            } catch {
                return 0
            }
        }.value
    }

    // MARK: - Timestamp parsing

    /// Parse pts_time values from ffmpeg showinfo filter output.
    private func parseShowinfoTimestamps(
        _ stderr: String, count: Int
    ) -> [Double] {
        var timestamps: [Double] = []
        guard let regex = try? NSRegularExpression(
            pattern: #"pts_time:\s*([\d.]+)"#
        ) else { return timestamps }
        let range = NSRange(stderr.startIndex..., in: stderr)
        for match in regex.matches(in: stderr, range: range) {
            guard let r = Range(match.range(at: 1), in: stderr),
                  let val = Double(stderr[r]) else { continue }
            timestamps.append(val)
        }
        // Fill missing with estimates
        while timestamps.count < count {
            let last = timestamps.last ?? 0
            timestamps.append(last + 10)
        }
        return timestamps
    }

    /// Rename frame_NNNN.jpg files to MM_SS.jpg using parsed timestamps.
    private func renameWithTimestamps(
        dir: URL, files: [String], timestamps: [Double]
    ) {
        let sorted = files.sorted()
        for (i, file) in sorted.enumerated() {
            let t = i < timestamps.count ? timestamps[i] : Double(i * 10)
            let mm = Int(t) / 60
            let ss = Int(t) % 60
            let newName = String(format: "%02d_%02d.jpg", mm, ss)
            let oldURL = dir.appendingPathComponent(file)
            let newURL = dir.appendingPathComponent(newName)
            if oldURL != newURL, !FileManager.default.fileExists(
                atPath: newURL.path
            ) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }
    }

    /// Parse MM_SS from filename to seconds.
    private func parseTimestamp(from filename: String) -> Int {
        let stem = (filename as NSString).deletingPathExtension
        let parts = stem.split(separator: "_")
        if parts.count >= 2,
           let mm = Int(parts[0]),
           let ss = Int(parts[1]) {
            return mm * 60 + ss
        }
        return 0
    }

    // MARK: - Perceptual hash dedup

    /// Remove consecutive near-duplicate frames in place using pHash,
    /// matching the approach in mooc/dedup-frames.py.
    private func deduplicateFrames(in dir: URL, files: [String]) {
        var prevHash: UInt64?

        for file in files {
            let url = dir.appendingPathComponent(file)
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(
                      forProposedRect: nil, context: nil, hints: nil
                  ) else { continue }

            let hash = perceptualHash(cgImage)

            if let prev = prevHash, hammingDistance(prev, hash) < dedupThreshold {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            prevHash = hash
        }
    }

    /// DCT-approximation perceptual hash (matches mooc/dedup-frames.py).
    /// Downsamples to 8x8 grayscale, compares each pixel to the median.
    /// Returns a 64-bit hash.
    private func perceptualHash(_ image: CGImage, hashSize: Int = 8) -> UInt64 {
        let size = hashSize
        let bytesPerRow = size
        let totalBytes = size * size
        var buf = [UInt8](repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &buf, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: 0
        ) else { return 0 }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Find median pixel value
        let sorted = buf.sorted()
        let median = sorted[sorted.count / 2]

        // Build 64-bit hash: bit i is 1 if pixel i > median
        var hash: UInt64 = 0
        for i in 0..<min(totalBytes, 64) where buf[i] > median {
            hash |= 1 << i
        }
        return hash
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - File helpers

    private func jpgFiles(
        in dir: URL, prefix: String? = nil
    ) -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return files
            .filter { $0.hasSuffix(".jpg") }
            .filter { prefix == nil || $0.hasPrefix(prefix!) }
            .sorted()
    }

    /// Run ffmpeg off the cooperative thread pool and return stderr.
    private func runFFmpeg(_ arguments: [String]) async -> String {
        await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["ffmpeg"] + arguments
            proc.standardOutput = Pipe()
            let errPipe = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return ""
            }
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    // MARK: - Cache

    private func loadCached(
        metaURL: URL, thumbDir: URL
    ) -> [SceneFrame]? {
        guard FileManager.default.fileExists(atPath: metaURL.path),
              let data = try? Data(contentsOf: metaURL),
              let entries = try? JSONSerialization.jsonObject(with: data)
                  as? [[String: Any]],
              !entries.isEmpty else { return nil }

        var frames: [SceneFrame] = []
        for entry in entries {
            guard let time = entry["time"] as? Int,
                  let file = entry["file"] as? String
            else { continue }
            let fileURL = thumbDir.appendingPathComponent(file)
            guard let image = NSImage(contentsOf: fileURL) else { continue }
            frames.append(
                SceneFrame(time: Double(time), image: image)
            )
        }
        return frames.isEmpty ? nil : frames
    }
}
