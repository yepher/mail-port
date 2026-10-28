import Foundation
import XCTest
@testable import MailPortCore

final class TabReorderingTests: XCTestCase {
    func testMoveFirstToLastAndBackPreservesOrderAndAccountIdentity() throws {
        let accounts = [Account(name: "Personal"), Account(name: "Work")]
        let tabs = WorkspaceTab.pinnedTabs(for: accounts)
        let moved = WorkspaceTab.reordered(tabs, moving: tabs[0], over: tabs[3])
        XCTAssertEqual(moved, [tabs[1], tabs[2], tabs[3], tabs[0]])
        XCTAssertEqual(WorkspaceTab.reordered(moved, moving: tabs[0], over: tabs[1]), tabs)
        XCTAssertEqual(Set(moved), Set(tabs))
        let saved = try JSONEncoder().encode(moved)
        XCTAssertEqual(try JSONDecoder().decode([WorkspaceTab].self, from: saved), moved)
        XCTAssertEqual(moved.last?.dataStoreIdentifier, accounts[0].id)
    }

    func testAdjacentMovesWorkInBothDirections() {
        let tabs = WorkspaceTab.pinnedTabs(for: [Account(name: "Personal"), Account(name: "Work")])
        XCTAssertEqual(WorkspaceTab.reordered(tabs, moving: tabs[1], over: tabs[2]), [tabs[0], tabs[2], tabs[1], tabs[3]])
        XCTAssertEqual(WorkspaceTab.reordered(tabs, moving: tabs[2], over: tabs[1]), [tabs[0], tabs[2], tabs[1], tabs[3]])
    }

    func testUnknownAndSelfDropsLeaveTabsUnchanged() {
        let tabs = WorkspaceTab.pinnedTabs(for: [Account(name: "Personal")])
        let unknown = WorkspaceTab(accountID: UUID(), service: .meet)
        XCTAssertEqual(WorkspaceTab.reordered(tabs, moving: tabs[0], over: tabs[0]), tabs)
        XCTAssertEqual(WorkspaceTab.reordered(tabs, moving: unknown, over: tabs[0]), tabs)
        XCTAssertEqual(WorkspaceTab.reordered(tabs, moving: tabs[0], over: unknown), tabs)
        XCTAssertEqual(WorkspaceTab.reordered([], moving: unknown, over: tabs[0]), [])
    }
}
