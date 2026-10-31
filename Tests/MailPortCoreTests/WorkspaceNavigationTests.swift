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
            + [WorkspaceTab(accountID: personal.id, service: .gmail)]
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
