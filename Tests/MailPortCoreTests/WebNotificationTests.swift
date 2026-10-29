import Foundation
import XCTest
@testable import MailPortCore

final class WebNotificationTests: XCTestCase {
    func testOnlyMatchingGoogleMainFramesMayDeliver() {
        XCTAssertTrue(WebNotificationMessage.allows(scheme: "https", host: "calendar.google.com", port: 443, mainFrame: true, service: .calendar))
        XCTAssertTrue(WebNotificationMessage.allows(scheme: "https", host: "mail.google.com", port: 0, mainFrame: true, service: .gmail))
        for host in ["accounts.google.com", "calendar.google.com.evil.test", "evil.test", "mail.google.com"] {
            XCTAssertFalse(WebNotificationMessage.allows(scheme: "https", host: host, port: 443, mainFrame: true, service: .calendar))
        }
        XCTAssertFalse(WebNotificationMessage.allows(scheme: "http", host: "calendar.google.com", port: 80, mainFrame: true, service: .calendar))
        XCTAssertFalse(WebNotificationMessage.allows(scheme: "https", host: "calendar.google.com", port: 8443, mainFrame: true, service: .calendar))
        XCTAssertFalse(WebNotificationMessage.allows(scheme: "https", host: "calendar.google.com", port: 443, mainFrame: false, service: .calendar))
        XCTAssertFalse(WebNotificationMessage.allows(scheme: "https", host: "calendar.google.com", port: 443, mainFrame: true, service: .gemini))
    }

    func testMalformedMessagesAreRejectedAndContentIsBounded() throws {
        for values: [String: Any] in [[:], ["kind":"execute", "id":"a"], ["kind":"show", "id":"../other"], ["kind":"show", "id":String(repeating:"a", count:129)]] {
            XCTAssertNil(WebNotificationMessage(values))
        }
        let message = try XCTUnwrap(WebNotificationMessage(["kind":"show", "id":"event-1", "title":String(repeating:"A", count:1000), "body":String(repeating:"B", count:4000), "tag":String(repeating:"C", count:1000), "silent":true]))
        XCTAssertEqual(message.title.count,256)
        XCTAssertEqual(message.body.count,2048)
        XCTAssertEqual(message.tag.count,256)
        XCTAssertTrue(message.silent)
        XCTAssertEqual(WebNotificationMessage(["kind":"permission", "id":"permission-1"])?.kind,.permission)
        XCTAssertEqual(WebNotificationMessage(["kind":"close", "id":"event-1"])?.kind,.close)
    }
}
