import Foundation
import XCTest
@testable import MailPortEmbedded

final class YouTubeDownloadTests: XCTestCase {
    @MainActor private func fixture(script: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPort-download-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let helper = directory.appendingPathComponent("helper")
        try ("#!/bin/sh\n" + script).write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (helper, directory.appendingPathComponent("saved audio.m4a"))
    }

    @MainActor func testHelperProgressReachesNativeObserver() async throws {
        let (helper, destination) = try fixture(script: "printf 'MAILPORT_PROGRESS: 42.0%%\\n'\nsleep 0.5\nwhile [ \"$1\" != \"--output\" ]; do shift; done\nshift\nprintf 'fixture media' > \"$1\"\n")
        let download = YouTubeDownload(helper: helper)
        var fractions: [Double] = []
        download.onProgress = { fraction, _ in if let fraction { fractions.append(fraction) } }
        try await download.save(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!, audio: true, destination: destination)
        XCTAssertTrue(fractions.contains(0.42))
    }

    @MainActor func testSuccessfulDownloadPublishesOnlyCompletedFile() async throws {
        let (helper, destination) = try fixture(script: "while [ \"$1\" != \"--output\" ]; do shift; done\nshift\nprintf 'fixture media' > \"$1\"\n")
        try await YouTubeDownload(helper: helper, ffmpeg: URL(fileURLWithPath: "/usr/bin/true")).save(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!, audio: true, destination: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "fixture media")
    }

    @MainActor func testVideoMetadataListsRealHeightsFromHelper() async throws {
        let (helper, _) = try fixture(script: "echo '{\"formats\":[{\"ext\":\"mp4\",\"vcodec\":\"avc1\",\"acodec\":\"mp4a\",\"height\":1080},{\"ext\":\"mp4\",\"vcodec\":\"avc1\",\"acodec\":\"mp4a\",\"height\":360}]}'\n")
        let heights = try await YouTubeDownload(helper: helper).resolutions(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!)
        XCTAssertEqual(heights, [1080, 360])
    }

    @MainActor func testFailurePreservesExistingDestination() async throws {
        let (helper, destination) = try fixture(script: "echo 'fixture failure' >&2\nexit 1\n")
        try "existing".write(to: destination, atomically: true, encoding: .utf8)
        do {
            try await YouTubeDownload(helper: helper, ffmpeg: URL(fileURLWithPath: "/usr/bin/true")).save(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!, audio: false, destination: destination)
            XCTFail("Expected helper failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("fixture failure")) }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
    }

    @MainActor func testCancellationDoesNotPublishAFile() async throws {
        let (helper, destination) = try fixture(script: "exec /bin/sleep 20\n")
        let download = YouTubeDownload(helper: helper)
        let pending = Task { try await download.save(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!, audio: true, destination: destination) }
        try await Task.sleep(for: .milliseconds(100))
        download.cancel()
        do { try await pending.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
