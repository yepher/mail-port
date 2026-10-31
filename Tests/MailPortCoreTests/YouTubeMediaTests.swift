import XCTest
@testable import MailPortCore

final class YouTubeMediaTests: XCTestCase {
    func testFilenameUsesChannelAndCanonicalVideoID() {
        let url = URL(string: "https://www.youtube.com/watch?v=abcdefghijk&list=ignored")!
        XCTAssertEqual(YouTubeMedia.suggestedBasename(metadata: ["channel": "Example Channel", "id": "wrong-id"], url: url), "Example_Channel_abcdefghijk")
        XCTAssertEqual(YouTubeMedia.suggestedBasename(metadata: ["channel": " ", "uploader": "Uploader"], url: url), "Uploader_abcdefghijk")
        XCTAssertEqual(YouTubeMedia.suggestedBasename(metadata: [:], url: url), "YouTube_abcdefghijk")
    }
    func testFilenameCannotEscapeDirectoryAndBoundsUTF8Length() {
        let url = URL(string: "https://www.youtube.com/shorts/abcdefghijk")!
        let name = YouTubeMedia.suggestedBasename(metadata: ["channel": "../../A/B:C\\D\n"], url: url)
        XCTAssertEqual(name, "A_B_C_D_abcdefghijk")
        let long = YouTubeMedia.suggestedBasename(metadata: ["channel": String(repeating: "界", count: 256)], url: url)
        XCTAssertLessThanOrEqual(long.utf8.count, 172)
        XCTAssertTrue(long.hasSuffix("_abcdefghijk"))
        XCTAssertEqual(YouTubeMedia.suggestedBasename(metadata: ["channel": "..."], url: url), "YouTube_abcdefghijk")
    }

    func testCanonicalURLDropsPlaylistAndRejectsUntrustedInput() {
        XCTAssertEqual(YouTubeMedia.videoURL(URL(string: "https://www.youtube.com/watch?v=abcdefghijk&list=private"))?.absoluteString,
                       "https://www.youtube.com/watch?v=abcdefghijk")
        XCTAssertNotNil(YouTubeMedia.videoURL(URL(string: "https://www.youtube.com/shorts/abcdefghijk")))
        for value in ["https://evil.test/watch?v=abcdefghijk", "https://www.youtube.com/watch?v=--exec", "http://www.youtube.com/watch?v=abcdefghijk", "https://user@www.youtube.com/watch?v=abcdefghijk"] {
            XCTAssertNil(YouTubeMedia.videoURL(URL(string: value)))
        }
    }
    func testResolutionChoicesExcludeAudioOnlyAndUnmergeableFormats() {
        let formats: [[String: Any]] = [
            ["ext": "mp4", "vcodec": "avc1", "acodec": "mp4a", "height": 360],
            ["ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": 1080],
            ["ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": 2160],
            ["ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": 1080],
            ["ext": "webm", "vcodec": "vp9", "acodec": "none", "height": 4320],
            ["ext": "mp4", "vcodec": "none", "acodec": "mp4a", "height": 720],
            ["ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": -1],
            ["ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": "bad"]
        ]
        XCTAssertEqual(YouTubeMedia.availableHeights(in: ["formats": formats]), [360])
        let audio: [String: Any] = ["ext": "m4a", "vcodec": "none", "acodec": "mp4a"]
        XCTAssertEqual(YouTubeMedia.availableHeights(in: ["formats": formats + [audio]]), [2160, 1080, 360])
        XCTAssertEqual(YouTubeMedia.availableHeights(in: [:]), [])
    }

    func testVideoPrefersSeparateStreamsAndExplicitHeightNeverFallsBackToLowerResolution() {
        let url = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
        let args = YouTubeMedia.arguments(url: url, audio: false, output: "/tmp/video.mp4", height: 1080, ffmpeg: "/opt/homebrew/bin/ffmpeg")
        let index = args.firstIndex(of: "--format")!
        XCTAssertEqual(args[index + 1], "bestvideo[ext=mp4][height=1080]+bestaudio[ext=m4a]/best[ext=mp4][vcodec!=none][acodec!=none][height=1080]")
        XCTAssertTrue(args.contains("--merge-output-format"))
        XCTAssertTrue(args.contains("/opt/homebrew/bin/ffmpeg"))
        let best = YouTubeMedia.arguments(url: url, audio: false, output: "/tmp/video.mp4")
        XCTAssertTrue(best.contains("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][vcodec!=none][acodec!=none]"))
    }

    func testHelperArgumentsIgnoreConfigurationAndNeverExportCookies() {
        let url = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
        let args = YouTubeMedia.arguments(url: url, audio: true, output: "/tmp/output with spaces.m4a")
        XCTAssertTrue(args.contains("--ignore-config"))
        XCTAssertTrue(args.contains("--no-playlist"))
        XCTAssertFalse(args.contains(where: { $0.contains("cookies") }))
        XCTAssertEqual(Array(args.suffix(2)), ["--", url.absoluteString])
        XCTAssertTrue(args.contains("/tmp/output with spaces.m4a"))
    }
}
