import Foundation
import XCTest
@testable import MailPortCore

final class YouTubeLinkDropTests: XCTestCase {
    func testUserExampleAndShareTimestampArePreserved() throws {
        let example = "https://www.youtube.com/watch?is=6EhoY10PE9DCIxqE&v=IHBNCtkQuGY&feature=youtu.be"
        XCTAssertEqual(YouTubeLinkDrop.url(from: example)?.absoluteString, example)
        let shared = try XCTUnwrap(YouTubeLinkDrop.url(from: " https://youtu.be/IHBNCtkQuGY?t=90\n"))
        XCTAssertEqual(shared.host, "www.youtube.com")
        XCTAssertEqual(shared.path, "/watch")
        let query = URLComponents(url: shared, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "v" })?.value, "IHBNCtkQuGY")
        XCTAssertEqual(query?.first(where: { $0.name == "t" })?.value, "90")
    }
    func testMobileShortsAndPlaylistLinksNormalizeToYouTube() {
        XCTAssertEqual(YouTubeLinkDrop.url(from: "https://m.youtube.com/shorts/IHBNCtkQuGY")?.host, "www.youtube.com")
        XCTAssertNotNil(YouTubeLinkDrop.url(from: "https://youtube.com/playlist?list=demo"))
    }
    func testRejectsOtherSitesFilesCredentialsAndMalformedDrops() {
        for text in ["https://youtube.com.evil.test/watch?v=IHBNCtkQuGY", "https://evil.test", "file:///tmp/test", "javascript:alert(1)", "https://user:pass@youtube.com/watch", "http://youtube.com/watch", "https://youtube.com:123/watch", "https://youtu.be/invalid", "https://youtu.be/IHBNCtkQuGY/extra", "two https://youtube.com links", "https://youtube.com\nhttps://evil.test"] {
            XCTAssertNil(YouTubeLinkDrop.url(from: text), text)
        }
    }
}
