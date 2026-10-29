import Foundation
import XCTest
@testable import MailPortCore

final class TabActivityTests: XCTestCase {
    func testUnreadCountsClearAndExpireWithoutTreatingUnknownAsZero() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = try XCTUnwrap(TabActivity(message: ["kind": "unread", "count": 12], service: .gmail, now: now))
        XCTAssertEqual(activity.unreadBadge(at: now), "12")
        XCTAssertNil(activity.unreadBadge(at: now.addingTimeInterval(301)))
        XCTAssertNil(TabActivity(message: ["kind": "unread", "count": 0], service: .gmail)?.unreadBadge(at: Date()))
        XCTAssertEqual(TabActivity(message: ["kind": "unread", "count": 1000], service: .gmail)?.unreadBadge(at: Date()), "999+")
        XCTAssertNil(TabActivity(message: ["kind": "unread", "count": -1], service: .gmail))
        XCTAssertNil(TabActivity(message: ["kind": "unread", "count": 4], service: .calendar))
        XCTAssertNil(TabActivity(message: ["kind": "unread"], service: .gmail))
    }

    func testCalendarDotStartsAtStartAndClearsAtEndWithOverlappingEvents() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let windows: [[String: Double]] = [
            ["start": start.timeIntervalSince1970 * 1000, "end": start.addingTimeInterval(60).timeIntervalSince1970 * 1000],
            ["start": start.addingTimeInterval(30).timeIntervalSince1970 * 1000, "end": start.addingTimeInterval(90).timeIntervalSince1970 * 1000]
        ]
        let activity = try XCTUnwrap(TabActivity(message: ["kind": "calendar", "events": windows], service: .calendar, now: start))
        XCTAssertFalse(activity.hasCurrentEvent(at: start.addingTimeInterval(-1)))
        XCTAssertTrue(activity.hasCurrentEvent(at: start))
        XCTAssertTrue(activity.hasCurrentEvent(at: start.addingTimeInterval(60)))
        XCTAssertFalse(activity.hasCurrentEvent(at: start.addingTimeInterval(90)))
        XCTAssertFalse(activity.hasCurrentEvent(at: start.addingTimeInterval(301)))
        XCTAssertNil(TabActivity(message: ["kind": "calendar", "events": windows], service: .gmail))
    }

    func testMalformedCalendarWindowsCannotLightTheDot() {
        for pair: [String: Double] in [["start": 1000, "end": 1000], ["start": 2000, "end": 1000], ["start": .nan, "end": 2000], ["start": 1000, "end": .infinity]] {
            XCTAssertNil(TabActivity(message: ["kind": "calendar", "events": [pair]], service: .calendar))
        }
    }
}
