import Foundation
import XCTest
@testable import MailPortCore

final class BrowserLinkRoutingTests: XCTestCase {
    func testScriptedAndNewWindowLinksOpenExternallyWithoutLinkActivated() throws {
        let url = try XCTUnwrap(URL(string: "https://example.org/article"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: url, service: .gmail, topLevel: true), url)
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: url, service: .gmail, topLevel: true, userLink: true), url)
        XCTAssertNil(BrowserLinkRouting.externalURL(for: url, service: .gmail, topLevel: false))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: url, service: .gmail, topLevel: false, userLink: true), url)
    }

    func testGoogleWrappersAndOtherGoogleProductsAreExternalToGmail() throws {
        let wrapped = try XCTUnwrap(URL(string: "https://www.google.com/url?q=https%3A%2F%2Fexample.org%2Farticle%3Fx%3D1%26y%3D2&source=gmail"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: wrapped, service: .gmail, topLevel: true)?.absoluteString, "https://example.org/article?x=1&y=2")
        let docs = try XCTUnwrap(URL(string: "https://docs.google.com/document/d/example/edit"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: docs, service: .gmail, topLevel: true), docs)
        let search = try XCTUnwrap(URL(string: "https://www.google.com/search?q=example"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: search, service: .gmail, topLevel: true), search)
        let unsafeWrapper = try XCTUnwrap(URL(string: "https://www.google.com/url?q=javascript%3Aalert(1)"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: unsafeWrapper, service: .gmail, topLevel: true), unsafeWrapper)
    }

    func testServiceNavigationAndSsoRedirectsStayInside() throws {
        for service in GoogleService.allCases {
            XCTAssertNil(BrowserLinkRouting.externalURL(for: service.url, service: service, topLevel: true))
        }
        let auth = try XCTUnwrap(URL(string: "https://accounts.google.com/ServiceLogin"))
        XCTAssertTrue(BrowserLinkRouting.isAuthenticationURL(auth))
        XCTAssertNil(BrowserLinkRouting.externalURL(for: auth, service: .gmail, topLevel: true))
        let sso = try XCTUnwrap(URL(string: "https://sso.example.org/saml"))
        XCTAssertNil(BrowserLinkRouting.externalURL(for: sso, service: .gmail, topLevel: true, authenticating: true))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: sso, service: .gmail, topLevel: true), sso)
    }

    func testAttachmentsDoNotTurnIntoBrowserTabsOrExemptFutureLinks() throws {
        let attachment = try XCTUnwrap(URL(string: "https://mail.google.com/mail/u/0/?ui=2&view=att&attid=0.1"))
        XCTAssertTrue(BrowserLinkRouting.isGmailAttachmentURL(attachment))
        XCTAssertFalse(BrowserLinkRouting.isGmailAttachmentURL(GoogleService.gmail.url))
        let file = try XCTUnwrap(URL(string: "https://mail-attachment.googleusercontent.com/file"))
        XCTAssertNil(BrowserLinkRouting.externalURL(for: file, service: .gmail, topLevel: true, download: true))
        XCTAssertNil(BrowserLinkRouting.externalURL(for: file, service: .gmail, topLevel: true, attachment: true))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: file, service: .gmail, topLevel: true), file)
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: file, service: .gmail, topLevel: true, userLink: true, attachment: true), file)
    }

    func testPlainHttpUsesTheSystemBrowserAndUnsafeSchemesAreNotLaunched() throws {
        let http = try XCTUnwrap(URL(string: "http://example.org/"))
        XCTAssertEqual(BrowserLinkRouting.externalURL(for: http, service: .gmail, topLevel: true), http)
        for value in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,example", "https://name:secret@example.org/"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(BrowserLinkRouting.externalURL(for: url, service: .gmail, topLevel: true))
        }
    }
}
