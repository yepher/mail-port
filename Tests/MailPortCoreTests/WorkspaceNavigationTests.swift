import XCTest
@testable import MailPortCore

final class WorkspaceNavigationTests: XCTestCase {
    private let work = Account(name: "Work", email: "alex@studio.com")
    private let personal = Account(name: "Personal", email: "alex@gmail.com")
    private let inbox = URL(string: "https://mail.google.com/mail/u/0/#search/atlas")!

    private func titles(_ items: [QuickSwitchItem]) -> [String] { items.map { "\($0.subtitle)/\($0.title)" } }

    func testGroupingFollowsAccountOrderAndKeepsEachAccountsTabOrder() {
        let tabs = [WorkspaceTab(accountID: personal.id, service: .calendar),
                    WorkspaceTab(accountID: work.id, service: .drive),
                    WorkspaceTab(accountID: personal.id, service: .gmail),
                    WorkspaceTab(accountID: work.id, service: .gmail)]
        XCTAssertEqual(WorkspaceTab.grouped(tabs, by: [work, personal]), [tabs[1], tabs[3], tabs[0], tabs[2]])
    }

    func testShortcutNumbersFollowTheGivenOrderAndStopAtNine() {
        let tabs = GoogleService.allCases.map { WorkspaceTab(accountID: work.id, service: $0) }
        XCTAssertEqual(tabs.count, 10)
        XCTAssertEqual(tabs.map { WorkspaceTab.shortcutNumber(of: $0, in: tabs) }, [1, 2, 3, 4, 5, 6, 7, 8, 9, nil])
        XCTAssertNil(WorkspaceTab.shortcutNumber(of: WorkspaceTab(accountID: UUID(), service: .gmail), in: tabs))
    }

    func testShortcutNumbersMatchTheSidebarWhenTabsWereOpenedOutOfOrder() {
        let personalMail = WorkspaceTab(accountID: personal.id, service: .gmail)
        let workMail = WorkspaceTab(accountID: work.id, service: .gmail)
        let shown = WorkspaceTab.grouped([personalMail, workMail], by: [work, personal])
        XCTAssertEqual(WorkspaceTab.shortcutNumber(of: workMail, in: shown), 1)
        XCTAssertEqual(WorkspaceTab.shortcutNumber(of: personalMail, in: shown), 2)
    }

    func testReorderingServicesKeepsOtherAccountsAndUpdatesShortcuts() {
        let mail = WorkspaceTab(accountID: work.id, service: .gmail)
        let calendar = WorkspaceTab(accountID: work.id, service: .calendar)
        let drive = WorkspaceTab(accountID: work.id, service: .drive)
        let other = WorkspaceTab(accountID: personal.id, service: .gmail)
        let moved = WorkspaceTab.reordered([mail, other, calendar, drive], moving: drive, over: mail)
        let shown = WorkspaceTab.grouped(moved, by: [work, personal])
        XCTAssertEqual(shown, [drive, mail, calendar, other])
        XCTAssertEqual(WorkspaceTab.shortcutNumber(of: drive, in: shown), 1)
        XCTAssertEqual(WorkspaceTab.shortcutNumber(of: other, in: shown), 4)
    }

    func testServiceNeighborsSkipOtherAccountsAndStopAtTheEnds() {
        let mail = WorkspaceTab(accountID: work.id, service: .gmail)
        let other = WorkspaceTab(accountID: personal.id, service: .gmail)
        let drive = WorkspaceTab(accountID: work.id, service: .drive)
        let tabs = [mail, other, drive]
        XCTAssertEqual(WorkspaceTab.neighbor(of: mail, in: tabs, offset: 1), drive)
        XCTAssertEqual(WorkspaceTab.neighbor(of: drive, in: tabs, offset: -1), mail)
        XCTAssertNil(WorkspaceTab.neighbor(of: mail, in: tabs, offset: -1))
        XCTAssertNil(WorkspaceTab.neighbor(of: drive, in: tabs, offset: 1))
    }

    func testSignInStatusRecognizesSignedOutPagesWithoutGuessingOnOthers() {
        func status(_ address: String, _ service: GoogleService = .gmail) -> Bool? {
            BrowserLinkRouting.signInRequired(at: URL(string: address)!, service: service)
        }
        XCTAssertEqual(status("https://accounts.google.com/v3/signin/identifier"), true)
        XCTAssertEqual(status("https://workspace.google.com/gmail/"), true)
        XCTAssertEqual(status("https://www.google.com/intl/en/gmail/about/"), true)
        XCTAssertEqual(status("https://calendar.google.com/calendar/about/", .calendar), true)
        XCTAssertEqual(status("https://mail.google.com/mail/u/0/#inbox"), false)
        XCTAssertEqual(status("https://calendar.google.com/calendar/u/0/r", .calendar), false)
        XCTAssertNil(status("https://support.google.com/mail/"), "Other pages say nothing about sign-in")
        XCTAssertNil(status("https://accounts.google.com/signin", .drive), "Only Mail and Calendar report status")
        XCTAssertNil(status("http://accounts.google.com/signin"))
    }

    func testZoomStepsThroughStopsAndStopsAtTheEnds() {
        XCTAssertEqual(PageZoom.stepped(from: 1, by: 1), 1.1)
        XCTAssertEqual(PageZoom.stepped(from: 1, by: -1), 0.9)
        XCTAssertEqual(PageZoom.stepped(from: 2, by: 1), 2)
        XCTAssertEqual(PageZoom.stepped(from: 0.5, by: -1), 0.5)
        XCTAssertEqual(PageZoom.stepped(from: 1.2, by: 1), 1.25, "Values between stops move to the next stop")
        XCTAssertEqual(PageZoom.stepped(from: 1.2, by: -1), 1.1)
        XCTAssertFalse(PageZoom.isValid(.nan))
        XCTAssertFalse(PageZoom.isValid(0))
        XCTAssertFalse(PageZoom.isValid(10))
        XCTAssertTrue(PageZoom.isValid(1.5))
    }

    func testMutingEndsAtItsTimeAndDefaultsToOff() {
        let now = Date()
        XCTAssertFalse(AccountNotificationSettings().isMuted(at: now))
        let muted = AccountNotificationSettings(mutedUntil: now.addingTimeInterval(60))
        XCTAssertTrue(muted.isMuted(at: now))
        XCTAssertFalse(muted.isMuted(at: now.addingTimeInterval(60)))
        XCTAssertTrue(AccountNotificationSettings(mutedUntil: .distantFuture).isMuted(at: now))
    }

    func testHiddenPreviewsRevealNoMessageText() {
        let hidden = AccountNotificationSettings(hidesPreviews: true)
        XCTAssertEqual(hidden.alertText(title: "Secret subject", body: "Secret body", service: .gmail).title, "New mail")
        XCTAssertEqual(hidden.alertText(title: "Secret subject", body: "Secret body", service: .gmail).body, "")
        XCTAssertEqual(hidden.alertText(title: "Board meeting", body: "", service: .calendar).title, "Calendar reminder")
        let shown = AccountNotificationSettings()
        XCTAssertEqual(shown.alertText(title: "Subject", body: "Body", service: .gmail).title, "Subject")
        XCTAssertEqual(shown.alertText(title: "", body: "Body", service: .calendar).title, "Calendar reminder")
    }

    func testTomorrowMorningIsEightOnTheNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let lateNight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 30)))
        let parts = calendar.dateComponents([.day, .hour, .minute], from: AccountNotificationSettings.tomorrowMorning(after: lateNight, calendar: calendar))
        XCTAssertEqual([parts.day, parts.hour, parts.minute], [8, 8, 0], "Works across a daylight saving change")
    }

    func testYouTubeKeepsItsOwnSubdomainsAndSendsOtherSitesOut() {
        func external(_ address: String, _ service: GoogleService = .youtube, userLink: Bool = true) -> URL? {
            BrowserLinkRouting.externalURL(for: URL(string: address)!, service: service, topLevel: true, userLink: userLink)
        }
        for address in ["https://www.youtube.com/watch?v=abc", "https://studio.youtube.com/channel/abc",
                        "https://consent.youtube.com/m", "https://accounts.youtube.com/accounts/SetSID", "https://youtube.com/"] {
            XCTAssertNil(external(address), address)
        }
        XCTAssertNotNil(external("https://example.com/"))
        XCTAssertNotNil(external("https://www.youtube.com.evil.example/"))
        XCTAssertNotNil(external("https://www.youtube.com/watch?v=abc", .gmail), "Video links in mail still open in the browser")
    }

    func testTranscriptKeepsTimedTextAndRejectsEmptyPages() throws {
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        let segments: [[String: Any]] = [["time": "0:18", "text": " Hello "], ["time": "", "text": "No time"], ["time": "1:00", "text": "  "], ["text": 5]]
        let transcript = try XCTUnwrap(VideoTranscript(message: ["title": "Talk", "segments": segments], url: url))
        XCTAssertEqual(transcript.text, "Talk\nhttps://www.youtube.com/watch?v=abc\n\n[0:18] Hello\nNo time\n")
        XCTAssertNil(VideoTranscript(message: ["title": "Talk", "segments": []], url: url), "No transcript must not save an empty file")
        XCTAssertNil(VideoTranscript(message: ["segments": [["text": "   "]]], url: url))
        XCTAssertNil(VideoTranscript(message: ["title": 5], url: url))
    }

    func testTranscriptFilenamesCannotEscapeTheChosenFolder() throws {
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        func name(_ title: String) throws -> String {
            try XCTUnwrap(VideoTranscript(message: ["title": title, "segments": [["text": "Hi"]]], url: url)).suggestedFilename
        }
        XCTAssertEqual(try name("A/B: C\\D"), "A-B- C-D transcript.txt")
        XCTAssertEqual(try name("../../etc/passwd"), "-..-etc-passwd transcript.txt")
        XCTAssertEqual(try name("...hidden"), "hidden transcript.txt")
        XCTAssertEqual(try name(""), "YouTube video transcript.txt")
        XCTAssertLessThanOrEqual(try name(String(repeating: "a", count: 500)).count, 140)
    }

    func testTranscriptButtonOnlyAppliesToYouTubeWatchPages() {
        func page(_ address: String, _ service: GoogleService = .youtube) -> Bool {
            VideoTranscript.isVideoPage(URL(string: address), service: service)
        }
        XCTAssertTrue(page("https://www.youtube.com/watch?v=abc&t=10"))
        XCTAssertFalse(page("https://www.youtube.com/"))
        XCTAssertFalse(page("https://www.youtube.com/watch"))
        XCTAssertFalse(page("https://www.youtube.com/watch?v="))
        XCTAssertFalse(page("https://www.youtube.com/shorts/abc"))
        XCTAssertFalse(page("https://www.youtube.com.evil.example/watch?v=abc"))
        XCTAssertFalse(page("https://www.youtube.com/watch?v=abc", .gmail))
    }

    func testPinsAcceptOnlyTheirOwnSecureServiceHost() throws {
        let pin = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "  Atlas  ", url: inbox))
        XCTAssertEqual(pin.name, "Atlas")
        XCTAssertTrue(pin.isValid)
        for address in ["https://accounts.google.com/signin", "http://mail.google.com/mail/", "https://mail.google.com.evil.example/",
                        "https://user:secret@mail.google.com/mail/", "https://calendar.google.com/calendar/u/0/r"] {
            XCTAssertNil(WorkspacePin(accountID: work.id, service: .gmail, name: "Page", url: URL(string: address)!), address)
        }
        XCTAssertNil(WorkspacePin(accountID: work.id, service: .gmail, name: "   ", url: inbox))
    }

    func testPinNamesAreBoundedAndTamperedPinsAreInvalid() throws {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(WorkspacePin(accountID: work.id, service: .gmail, name: long, url: inbox)?.name.count, WorkspacePin.maximumNameLength)
        let pin = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Atlas", url: inbox))
        let saved = try XCTUnwrap(String(data: JSONEncoder().encode(pin), encoding: .utf8))
        let tampered = saved.replacingOccurrences(of: "mail.google.com", with: "evil.example")
        XCTAssertNotEqual(saved, tampered)
        XCTAssertFalse(try JSONDecoder().decode(WorkspacePin.self, from: Data(tampered.utf8)).isValid)
    }

    func testPinsReorderInEitherDirectionWithoutDisturbingOtherAccounts() throws {
        let a = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "A", url: inbox))
        let other = try XCTUnwrap(WorkspacePin(accountID: personal.id, service: .gmail, name: "Other", url: inbox))
        let b = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "B", url: inbox))
        let c = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "C", url: inbox))
        let pins = [a, other, b, c]
        func workOrder(_ list: [WorkspacePin]) -> [String] { list.filter { $0.accountID == work.id }.map(\.name) }
        XCTAssertEqual(workOrder(WorkspacePin.reordered(pins, moving: a, over: c)), ["B", "C", "A"])
        XCTAssertEqual(workOrder(WorkspacePin.reordered(pins, moving: c, over: a)), ["C", "A", "B"])
        XCTAssertEqual(workOrder(WorkspacePin.reordered(pins, moving: a, over: b)), ["B", "A", "C"])
        XCTAssertEqual(WorkspacePin.reordered(pins, moving: a, over: c).filter { $0.accountID == personal.id }, [other])
        XCTAssertEqual(WorkspacePin.reordered(pins, moving: a, over: other), pins, "Pins cannot cross accounts")
        XCTAssertEqual(WorkspacePin.reordered(pins, moving: a, over: a), pins)
    }

    func testPinNeighborsSkipOtherAccountsAndStopAtTheEnds() throws {
        let a = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "A", url: inbox))
        let other = try XCTUnwrap(WorkspacePin(accountID: personal.id, service: .gmail, name: "Other", url: inbox))
        let b = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "B", url: inbox))
        let pins = [a, other, b]
        XCTAssertEqual(WorkspacePin.neighbor(of: a, in: pins, offset: 1), b)
        XCTAssertEqual(WorkspacePin.neighbor(of: b, in: pins, offset: -1), a)
        XCTAssertNil(WorkspacePin.neighbor(of: a, in: pins, offset: -1))
        XCTAssertNil(WorkspacePin.neighbor(of: b, in: pins, offset: 1))
    }

    func testEmptyQueryListsOpenTabsThenPinsButNotClosedServices() throws {
        let tabs = WorkspaceTab.pinnedTabs(for: [work])
        let pin = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Atlas", url: inbox))
        XCTAssertEqual(titles(QuickSwitch.items(accounts: [work, personal], tabs: tabs, pins: [pin], query: " ")),
                       ["Work/Mail", "Work/Calendar", "Work · Mail/Atlas"])
    }

    func testEveryWordMustMatchAndClosedServicesCanBeFound() {
        let tabs = WorkspaceTab.pinnedTabs(for: [work, personal])
        XCTAssertEqual(titles(QuickSwitch.items(accounts: [work, personal], tabs: tabs, pins: [], query: "PERSONAL cal")), ["Personal/Calendar"])
        XCTAssertEqual(titles(QuickSwitch.items(accounts: [work, personal], tabs: tabs, pins: [], query: "work drive")), ["Work/Drive"])
        XCTAssertEqual(titles(QuickSwitch.items(accounts: [work, personal], tabs: tabs, pins: [], query: "studio gmail")), ["Work/Mail"])
        XCTAssertTrue(QuickSwitch.items(accounts: [work, personal], tabs: tabs, pins: [], query: "work nothing").isEmpty)
    }

    func testResultsLeaveOutTabsAndPinsForMissingAccounts() throws {
        let tabs = WorkspaceTab.pinnedTabs(for: [personal])
        let pin = try XCTUnwrap(WorkspacePin(accountID: personal.id, service: .gmail, name: "Atlas", url: inbox))
        XCTAssertTrue(QuickSwitch.items(accounts: [work], tabs: tabs, pins: [pin], query: "").isEmpty)
    }
}
