import AppKit
import WebKit
import XCTest
import MailPortCore
@testable import MailPortEmbedded

final class YouTubeLinkDropViewTests: XCTestCase {
    @MainActor func testURLAndPlainTextPasteboardsAreAcceptedOnlyForYouTube() throws {
        let browser = BrowserTab(account: Account(name: "Fixture"), service: .youtube, store: .nonPersistent(), loadsInitialPage: false)
        defer { browser.discardForSecurity() }
        let view = try XCTUnwrap(browser.webView as? LinkDropWebView)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([NSURL(string: "https://youtu.be/IHBNCtkQuGY?t=90")!])
        XCTAssertEqual(view.droppedYouTubeURL(from: board)?.host, "www.youtube.com")
        board.clearContents()
        board.setString("https://www.youtube.com/watch?is=6EhoY10PE9DCIxqE&v=IHBNCtkQuGY&feature=youtu.be", forType: .string)
        XCTAssertEqual(view.droppedYouTubeURL(from: board)?.path, "/watch")
        var received: URL?
        view.onYouTubeLinkDrop = { received = $0; return true }
        XCTAssertTrue(view.openDroppedYouTubeLink(from: board))
        XCTAssertEqual(received?.host, "www.youtube.com")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(received), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value, "IHBNCtkQuGY")
        received = nil
        view.acceptsYouTubeLinks = false
        XCTAssertFalse(view.openDroppedYouTubeLink(from: board))
        XCTAssertNil(received)
        XCTAssertNil(view.droppedYouTubeURL(from: board))
        browser.discardForSecurity()
        XCTAssertNil(view.onYouTubeLinkDrop)
        let mail = BrowserTab(account: Account(name: "Fixture mail"), service: .gmail, store: .nonPersistent(), loadsInitialPage: false)
        defer { mail.discardForSecurity() }
        XCTAssertFalse(try XCTUnwrap(mail.webView as? LinkDropWebView).acceptsYouTubeLinks)
    }
}
