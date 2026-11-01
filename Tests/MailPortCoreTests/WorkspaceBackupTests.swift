import Foundation
import XCTest
@testable import MailPortCore

final class WorkspaceBackupTests: XCTestCase {
    private func fixture() -> WorkspaceBackup {
        let account = Account(name: "Work", email: "alex@example.com", color: .teal)
        let tab = WorkspaceTab(accountID: account.id, service: .youtube)
        let pin = WorkspacePin(accountID: account.id, service: .youtube, name: "Watch later", url: URL(string: "https://www.youtube.com/playlist?list=WL")!)!
        return WorkspaceBackup(accounts: [account], tabs: [tab], pins: [pin], collapsed: [account.id], badgeExcluded: [account.id], notifications: [account.id: AccountNotificationSettings(hidesPreviews: true)], defaultMailAccount: account.id, layout: "tabBar", shortcutHints: false, zoom: ["youtube": 1.25], videoOpacity: 0.4)
    }
    func testRoundTripAndRestoreRemapsEveryAccountReference() throws {
        let original = fixture()
        let decoded = try WorkspaceBackup.decode(original.encoded())
        let imported = try decoded.importing(alongside: original.accounts)
        let id = try XCTUnwrap(imported.accounts.first?.id)
        XCTAssertNotEqual(id, original.accounts[0].id)
        XCTAssertEqual(imported.accounts[0].name, "Work (restored)")
        XCTAssertEqual(imported.accounts[0].email, original.accounts[0].email)
        XCTAssertEqual(imported.tabs[0].accountID, id)
        XCTAssertEqual(imported.pins[0].accountID, id)
        XCTAssertNotEqual(imported.pins[0].id, original.pins[0].id)
        XCTAssertEqual(imported.collapsed, [id]); XCTAssertEqual(imported.badgeExcluded, [id])
        XCTAssertEqual(imported.defaultMailAccount, id)
        XCTAssertEqual(imported.notifications[id]?.hidesPreviews, true)
        XCTAssertEqual(imported.zoom, original.zoom); XCTAssertEqual(imported.videoOpacity, 0.4)
        try imported.validate()
    }
    func testRejectsUnknownVersionDuplicateAccountsAndDanglingReferences() throws {
        var backup = fixture(); backup.version = 2
        XCTAssertThrowsError(try backup.encoded())
        backup = fixture(); backup.accounts += backup.accounts
        XCTAssertThrowsError(try backup.encoded())
        backup = fixture(); backup.tabs.append(WorkspaceTab(accountID: UUID(), service: .gmail))
        XCTAssertThrowsError(try backup.encoded())
        backup = fixture(); backup.defaultMailAccount = UUID()
        XCTAssertThrowsError(try backup.encoded())
    }
    func testRejectsUnsafePinURLsAndInvalidZoomBeforeRestore() throws {
        let data = try fixture().encoded()
        let text = String(decoding: data, as: UTF8.self)
        let malicious = text.replacingOccurrences(of: "www.youtube.com", with: "evil.example")
        XCTAssertThrowsError(try WorkspaceBackup.decode(Data(malicious.utf8)))
        var backup = fixture(); backup.zoom = ["youtube": 100]
        XCTAssertThrowsError(try backup.importing(alongside: []))
        XCTAssertThrowsError(try WorkspaceBackup.decode(Data(repeating: 32, count: 5_000_001)))
    }
    func testExportContainsOnlyAllowlistedConfiguration() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture().encoded()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["version", "accounts", "tabs", "pins", "collapsed", "badgeExcluded", "notifications", "defaultMailAccount", "layout", "shortcutHints", "zoom", "videoOpacity"]))
        XCTAssertNil(json["youtubeMediaDownloads"]); XCTAssertNil(json["cookies"]); XCTAssertNil(json["pinState"])
    }
}
