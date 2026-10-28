import Foundation
import XCTest
@testable import MailPortCore

final class TabClosingTests: XCTestCase {
    private let personalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let workID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var tabs: [WorkspaceTab] {
        [
            WorkspaceTab(accountID: personalID, service: .gmail),
            WorkspaceTab(accountID: personalID, service: .calendar),
            WorkspaceTab(accountID: workID, service: .gmail),
            WorkspaceTab(accountID: workID, service: .meet)
        ]
    }

    func testClosingFirstSelectedTabSelectsNextTab() {
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: tabs[0], in: tabs, selected: tabs[0]), tabs[1])
    }

    func testClosingMiddleSelectedTabSelectsRightHandNeighbor() {
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: tabs[1], in: tabs, selected: tabs[1]), tabs[2])
    }

    func testClosingLastSelectedTabSelectsPreviousTab() {
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: tabs[3], in: tabs, selected: tabs[3]), tabs[2])
    }

    func testClosingOnlySelectedTabLeavesNoSelection() {
        XCTAssertNil(WorkspaceTab.selection(afterClosing: tabs[0], in: [tabs[0]], selected: tabs[0]))
    }

    func testClosingBackgroundTabPreservesSelectedTab() {
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: tabs[1], in: tabs, selected: tabs[3]), tabs[3])
    }

    func testUnknownTabDoesNotChangeSelection() {
        let unknown = WorkspaceTab(accountID: workID, service: .drive)
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: unknown, in: tabs, selected: tabs[1]), tabs[1])
        XCTAssertNil(WorkspaceTab.selection(afterClosing: unknown, in: [], selected: nil))
    }

    func testClosingWithoutSelectionDoesNotSelectAnUnrelatedTab() {
        XCTAssertNil(WorkspaceTab.selection(afterClosing: tabs[0], in: tabs, selected: nil))
    }

    func testSameServiceInAnotherAccountIsNotTheClosedTab() {
        XCTAssertEqual(WorkspaceTab.selection(afterClosing: tabs[0], in: tabs, selected: tabs[2]), tabs[2])
        XCTAssertEqual(tabs[2].dataStoreIdentifier, workID)
        XCTAssertNotEqual(tabs[0].dataStoreIdentifier, tabs[2].dataStoreIdentifier)
    }

    func testTabPersistenceRoundTripsEveryServiceAndAccountIdentity() throws {
        let original = [personalID, workID].flatMap { id in
            GoogleService.allCases.map { WorkspaceTab(accountID: id, service: $0) }
        }
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([WorkspaceTab].self, from: encoded)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.map(\.id), original.map(\.id))
        XCTAssertEqual(restored.map(\.dataStoreIdentifier), original.map(\.dataStoreIdentifier))
        XCTAssertEqual(try JSONDecoder().decode([WorkspaceTab].self, from: JSONEncoder().encode([WorkspaceTab]())), [])
    }
}
