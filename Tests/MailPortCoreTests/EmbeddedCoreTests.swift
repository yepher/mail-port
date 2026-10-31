import Foundation
import XCTest
@testable import MailPortCore

final class EmbeddedCoreTests: XCTestCase {
    func testTabIdentityRemainsStableAndSeparatesServices() {
        let accountID = UUID()
        let mail = WorkspaceTab(accountID: accountID, service: .gmail)
        XCTAssertEqual(mail, WorkspaceTab(accountID: accountID, service: .gmail))
        XCTAssertEqual(mail.id, "\(accountID.uuidString):gmail")
        XCTAssertNotEqual(mail, WorkspaceTab(accountID: accountID, service: .calendar))
        XCTAssertEqual(Set([mail, mail]).count, 1)
    }

    func testServicesShareOneAccountStoreAndOtherAccountsStayIsolated() {
        let first = UUID(), second = UUID()
        let mail = WorkspaceTab(accountID: first, service: .gmail)
        let calendar = WorkspaceTab(accountID: first, service: .calendar)
        XCTAssertEqual(mail.dataStoreIdentifier, calendar.dataStoreIdentifier)
        XCTAssertEqual(mail.dataStoreIdentifier, first)
        for service in GoogleService.allCases {
            XCTAssertNotEqual(mail.dataStoreIdentifier, WorkspaceTab(accountID: second, service: service).dataStoreIdentifier)
        }
    }

    func testPinnedTabsFollowAccountOrderWithMailAndCalendarTogether() {
        let personal = Account(name: "Personal"), work = Account(name: "Work")
        XCTAssertEqual(WorkspaceTab.pinnedTabs(for: [personal, work]), [
            WorkspaceTab(accountID: personal.id, service: .gmail),
            WorkspaceTab(accountID: personal.id, service: .calendar),
            WorkspaceTab(accountID: work.id, service: .gmail),
            WorkspaceTab(accountID: work.id, service: .calendar)
        ])
        XCTAssertEqual(WorkspaceTab.pinnedTabs(for: []), [])
    }

    func testEditingAnAccountPreservesTabAndStoreIdentity() {
        var account = Account(name: "Before", email: "first@example.com", color: .teal)
        let before = WorkspaceTab.pinnedTabs(for: [account])
        account.name = "After"
        account.email = "renamed@example.com"
        account.color = .orange
        let after = WorkspaceTab.pinnedTabs(for: [account])
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.map(\.dataStoreIdentifier), after.map(\.dataStoreIdentifier))
    }

    func testMailtoPreservesPlusRecipientsAndMultilineBody() throws {
        let compose = try GmailCompose(mailto: URL(string: "mailto:person+tag@example.com?cc=team%40example.com&subject=Hello%20%26%20%E2%9C%93&body=First%0D%0ASecond%2Bthird")!)
        XCTAssertEqual(compose.to, "person+tag@example.com")
        XCTAssertEqual(compose.cc, "team@example.com")
        XCTAssertEqual(compose.subject, "Hello & ✓")
        XCTAssertEqual(compose.body, "First\r\nSecond+third")
        XCTAssertTrue(compose.url.absoluteString.contains("person%2Btag"))
        let items = URLComponents(url: compose.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "body" }?.value, compose.body)
    }

    func testMailtoRejectsOtherSchemesAndHeaderInjection() {
        for value in [
            "https://example.com/", "mailto://example.com/person",
            "mailto:person@example.com?subject=Hello%0ABcc:other@example.com",
            "mailto:person@example.com%0D%0ABcc:other@example.com",
            "mailto:person@example.com?cc=other@example.com%0D%0ASubject:bad"
        ] {
            XCTAssertThrowsError(try GmailCompose(mailto: URL(string: value)!), value)
        }
    }

    func testOptionalEmailValidationAndWhitespaceNormalization() throws {
        let account = try Account(name: "  Personal \n", email: " person@example.com ").validated()
        XCTAssertEqual(account.name, "Personal")
        XCTAssertEqual(account.email, "person@example.com")
        XCTAssertEqual(try Account(name: "Work").validated().email, "")
        XCTAssertThrowsError(try Account(name: " \n").validated())
        XCTAssertThrowsError(try Account(name: "Work", email: "not-an-email").validated())
    }

    func testAccountPersistenceRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        XCTAssertEqual(try store.load(), [])
        let accounts = [Account(name: "Personal", email: "person@example.com", color: .teal), Account(name: "Work", color: .orange)]
        try store.save(accounts)
        XCTAssertEqual(try store.load(), accounts)
        XCTAssertEqual(WorkspaceTab.pinnedTabs(for: try store.load()), WorkspaceTab.pinnedTabs(for: accounts))
    }

    func testCorruptAccountDataIsReportedWithoutReplacingIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AccountStore(directory: directory)
        let corrupt = Data("not a valid account file".utf8)
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    func testDuplicateAccountIDsCannotOverwriteValidAccountData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        let account = Account(name: "Personal")
        try store.save([account])
        let original = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.save([account, account]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MailPortEmbeddedTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testHexColorsAcceptHTMLFormsAndRejectEverythingElse() {
        XCTAssertEqual(HexColor("#1a73e8")?.code, "#1A73E8")
        XCTAssertEqual(HexColor("  1A73E8 ")?.code, "#1A73E8")
        XCTAssertEqual(HexColor("#F80")?.code, "#FF8800")
        XCTAssertEqual(HexColor("#123456")?.red, 0x12)
        for text in ["", "#", "#12", "#1234", "#12345", "#1234567", "#12345678", "#GGGGGG", "red", "##123456", "#１２３"] {
            XCTAssertNil(HexColor(text), text)
        }
    }

    func testWheelValuesRoundToCodesAndStayInRange() {
        XCTAssertEqual(HexColor(red: 1, green: 0, blue: 0.5).code, "#FF0080")
        XCTAssertEqual(HexColor(red: 1.4, green: -0.2, blue: 0).code, "#FF0000")
    }

    func testLabelsUseWhicheverTextIsMoreReadable() throws {
        XCTAssertTrue(try XCTUnwrap(HexColor("#FFFF00")).prefersDarkText)
        XCTAssertTrue(try XCTUnwrap(HexColor("#FFFFFF")).prefersDarkText)
        XCTAssertFalse(try XCTUnwrap(HexColor("#000000")).prefersDarkText)
        XCTAssertFalse(try XCTUnwrap(HexColor("#1A237E")).prefersDarkText)
    }

    func testCustomColorRoundTripsAndNormalizes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        try store.save([Account(name: "Work", color: .purple, customColor: "#f80")])
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.customColor, "#FF8800")
        XCTAssertEqual(loaded.color, .purple)
    }

    func testAccountListsWithoutACustomColorStillLoad() throws {
        let json = #"[{"id":"11111111-1111-4111-8111-111111111111","name":"Work","email":"","color":"teal"}]"#
        let account = try XCTUnwrap(JSONDecoder().decode([Account].self, from: Data(json.utf8)).first)
        XCTAssertNil(account.customColor)
        XCTAssertNil(account.hexColor)
        XCTAssertEqual(account.color, .teal)
    }

    func testBadSavedColorFallsBackInsteadOfBlockingTheAccountList() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"11111111-1111-4111-8111-111111111111","name":"Work","email":"","color":"teal","customColor":"not-a-color"}]"#
        try Data(json.utf8).write(to: store.fileURL)
        let account = try XCTUnwrap(store.load().first)
        XCTAssertNil(account.customColor)
        XCTAssertEqual(account.color, .teal)
    }

    func testOlderBuildsCanStillDecodeAnAccountWithACustomColor() throws {
        struct OlderAccount: Decodable { let id: UUID; let name: String; let email: String; let color: AccountColor }
        let data = try JSONEncoder().encode(Account(name: "Work", color: .rose, customColor: "#123456"))
        XCTAssertEqual(try JSONDecoder().decode(OlderAccount.self, from: data).color, .rose)
    }
}
