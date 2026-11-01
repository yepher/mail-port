import Foundation
import XCTest
@testable import MailPortCore

final class NotificationScheduleTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testWorkAndPersonalAreComplementaryIncludingWeekendAndExactBoundaries() {
        let work = NotificationSchedule()
        let personal = NotificationSchedule(mode: .muteDuring)
        let c = calendar()
        for (text, workAllowed) in [
            ("2026-11-02T08:59:59Z", false), ("2026-11-02T09:00:00Z", true),
            ("2026-11-02T16:59:59Z", true), ("2026-11-02T17:00:00Z", false),
            ("2026-11-07T12:00:00Z", false), ("2026-11-08T12:00:00Z", false)
        ] {
            XCTAssertEqual(work.isMuted(at: date(text), calendar: c), !workAllowed, text)
            XCTAssertEqual(personal.isMuted(at: date(text), calendar: c), workAllowed, text)
        }
    }
    func testOvernightWindowBelongsToStartingDay() {
        let schedule = NotificationSchedule(weekdays: [6], startMinute: 22 * 60, endMinute: 7 * 60)
        let c = calendar()
        for (text, inside) in [
            ("2026-11-06T06:00:00Z", false), ("2026-11-06T22:00:00Z", true),
            ("2026-11-07T06:59:59Z", true), ("2026-11-07T07:00:00Z", false),
            ("2026-11-07T23:00:00Z", false)
        ] { XCTAssertEqual(schedule.contains(date(text), calendar: c), inside, text) }
    }
    func testManualMuteWinsAndClearingItResumesSchedule() {
        let c = calendar(); let morning = date("2026-11-02T10:00:00Z")
        var settings = AccountNotificationSettings(mutedUntil: morning.addingTimeInterval(3600), schedule: NotificationSchedule())
        XCTAssertTrue(settings.isMuted(at: morning, calendar: c))
        settings.mutedUntil = nil
        XCTAssertFalse(settings.isMuted(at: morning, calendar: c))
        XCTAssertTrue(settings.isMuted(at: date("2026-11-02T20:00:00Z"), calendar: c))
    }
    func testDisabledScheduleAndAllDaySelection() {
        XCTAssertFalse(NotificationSchedule(enabled: false).isMuted(at: date("2026-11-08T12:00:00Z"), calendar: calendar()))
        let allDay = NotificationSchedule(weekdays: [2], startMinute: 0, endMinute: 0)
        XCTAssertTrue(allDay.contains(date("2026-11-02T00:00:00Z"), calendar: calendar()))
        XCTAssertTrue(allDay.contains(date("2026-11-02T23:59:59Z"), calendar: calendar()))
        XCTAssertFalse(allDay.contains(date("2026-11-03T00:00:00Z"), calendar: calendar()))
    }
    func testLocalTimeFollowsTimeZoneChanges() {
        let instant = date("2026-11-02T09:30:00Z"); let schedule = NotificationSchedule()
        XCTAssertFalse(schedule.isMuted(at: instant, calendar: calendar("UTC")))
        XCTAssertTrue(schedule.isMuted(at: instant, calendar: calendar("America/Chicago")))
    }
    func testDaylightSavingSpringGapAndRepeatedFallHour() {
        let c = calendar("America/Chicago")
        let spring = NotificationSchedule(weekdays: [1], startMinute: 90, endMinute: 210)
        XCTAssertTrue(spring.contains(date("2026-03-08T07:45:00Z"), calendar: c))
        XCTAssertTrue(spring.contains(date("2026-03-08T08:15:00Z"), calendar: c))
        XCTAssertFalse(spring.contains(date("2026-03-08T08:30:00Z"), calendar: c))
        let fall = NotificationSchedule(weekdays: [1], startMinute: 90, endMinute: 150)
        XCTAssertTrue(fall.contains(date("2026-11-01T06:45:00Z"), calendar: c))
        XCTAssertTrue(fall.contains(date("2026-11-01T07:45:00Z"), calendar: c))
        XCTAssertFalse(fall.contains(date("2026-11-01T08:30:00Z"), calendar: c))
    }
    func testLegacySettingsDecodeAndScheduleRoundTrip() throws {
        let legacy = try JSONDecoder().decode(AccountNotificationSettings.self, from: Data(#"{"hidesPreviews":false}"#.utf8))
        XCTAssertNil(legacy.schedule)
        XCTAssertFalse(legacy.isMuted(at: Date()))
        let configured = AccountNotificationSettings(hidesPreviews: true, schedule: NotificationSchedule(mode: .muteDuring))
        XCTAssertEqual(try JSONDecoder().decode(AccountNotificationSettings.self, from: JSONEncoder().encode(configured)), configured)
    }
    func testInvalidScheduleIsRejectedByDecoderAndBackup() throws {
        for schedule in [NotificationSchedule(weekdays: []), NotificationSchedule(weekdays: [8]), NotificationSchedule(startMinute: -1), NotificationSchedule(endMinute: 1440)] {
            XCTAssertThrowsError(try JSONDecoder().decode(NotificationSchedule.self, from: JSONEncoder().encode(schedule)))
            let account = Account(name: "Fixture")
            let backup = WorkspaceBackup(accounts: [account], tabs: [], pins: [], notifications: [account.id: AccountNotificationSettings(schedule: schedule)])
            XCTAssertThrowsError(try backup.encoded())
        }
    }
}
