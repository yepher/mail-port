import AppKit
import Foundation
import MailPortCore

/// Runs only locally installed helpers, with explicit arguments and no exported cookies.
@MainActor
final class YouTubeDownload {
    private var process: Process?
    private var cancelled = false
    private let executable: URL?
    private let merger: URL?

    init(helper: URL? = nil, ffmpeg: URL? = nil) {
        executable = helper ?? Self.helper
        merger = ffmpeg ?? Self.ffmpeg
    }

    private static func installed(_ name: String) -> URL? {
        ["/opt/homebrew/bin/", "/usr/local/bin/"].map { URL(fileURLWithPath: $0 + name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static var helper: URL? { installed("yt-dlp") }
    static var ffmpeg: URL? { installed("ffmpeg") }

    func cancel() {
        cancelled = true
        if process?.isRunning == true { process?.interrupt() }
    }

    func resolutions(url: URL) async throws -> [Int] {
        let details = try await self.details(url: url)
        guard !details.heights.isEmpty else { throw failure("No downloadable MP4 video with audio was found. Update yt-dlp and Deno, then try again.") }
        return details.heights
    }

    func details(url: URL) async throws -> (heights: [Int], basename: String) {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let metadata = folder.appendingPathComponent("metadata.json")
        try await run(arguments: ["--ignore-config", "--no-playlist", "--skip-download", "--dump-single-json", "--quiet", "--", url.absoluteString], folder: folder, output: metadata)
        let attributes = try FileManager.default.attributesOfItem(atPath: metadata.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 20_000_000 else { throw failure("YouTube returned too much video metadata.") }
        let data = try Data(contentsOf: metadata)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("YouTube returned invalid video metadata.") }
        return (YouTubeMedia.availableHeights(in: object), YouTubeMedia.suggestedBasename(metadata: object, url: url))
    }

    func save(url: URL, audio: Bool, destination: URL, height: Int? = nil) async throws {
        if !audio && merger == nil { throw failure("Video saving requires FFmpeg to merge high-resolution video and audio. Open Terminal and run: brew install ffmpeg") }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let staging = folder.appendingPathComponent(audio ? "audio.m4a" : "video.mp4")
        try await run(arguments: YouTubeMedia.arguments(url: url, audio: audio, output: staging.path, height: height, ffmpeg: merger?.path), folder: folder)
        guard FileManager.default.fileExists(atPath: staging.path) else { throw failure("The download finished without creating the requested media file.") }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MailPort-media-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func run(arguments: [String], folder: URL, output: URL? = nil) async throws {
        guard !cancelled else { throw CancellationError() }
        guard let helper = executable else { throw failure("Install the download tools in Terminal: brew install yt-dlp deno ffmpeg") }
        let log = folder.appendingPathComponent("errors.txt")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errors = try FileHandle(forWritingTo: log)
        defer { try? errors.close(); process = nil }
        var stdout = FileHandle.nullDevice
        if let output {
            FileManager.default.createFile(atPath: output.path, contents: nil)
            stdout = try FileHandle(forWritingTo: output)
        }
        defer { if output != nil { try? stdout.close() } }
        let task = Process()
        task.executableURL = helper
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        task.standardOutput = stdout
        task.standardError = errors
        process = task
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do { try task.run() } catch { task.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        guard !cancelled else { throw CancellationError() }
        guard status == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw failure("YouTube download failed. Update yt-dlp and Deno if needed. The selected format may no longer be available, or the video may require sign-in. " + String(details.suffix(1800)))
        }
    }

    private func failure(_ text: String) -> NSError {
        NSError(domain: "MailPortMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
