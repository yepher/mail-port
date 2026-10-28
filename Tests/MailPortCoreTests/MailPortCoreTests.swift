import Foundation
import XCTest
@testable import MailPortCore

final class MailPortCoreTests: XCTestCase {
    func testEveryServiceLaunchesUsingItsOwnStableAccountProfile() throws {
        let root = URL(fileURLWithPath: "/tmp/MailPort Tests/Profiles", isDirectory: true)
        let account = Account(name: "Personal")
        let another = Account(name: "Work")
        for service in GoogleService.allCases {
            let plan = try BrowserLaunchPlan(account: account, url: service.url, profilesDirectory: root)
            XCTAssertEqual(plan.profileDirectory.lastPathComponent, account.id.uuidString)
            XCTAssertEqual(plan.arguments.last, "--app=\(service.url.absoluteString)")
            XCTAssertEqual(plan.arguments.count, 4)
            XCTAssertNotEqual(plan.profileDirectory, try BrowserLaunchPlan(account: another, url: service.url, profilesDirectory: root).profileDirectory)
        }
    }

    func testLaunchRejectsUntrustedHostsAndSchemes() {
        let account = Account(name: "Personal")
        let root = URL(fileURLWithPath: "/tmp/Profiles")
        let invalid = [
            "javascript:alert(1)", "file:///etc/passwd", "http://mail.google.com/",
            "https://mail.google.com.evil.test/", "https://evil.test/?next=https://mail.google.com",
            "https://someone@mail.google.com/", "https://mail.google.com:8443/"
        ]
        for address in invalid {
            XCTAssertThrowsError(try BrowserLaunchPlan(account: account, url: URL(string: address)!, profilesDirectory: root), address)
        }
    }

    func testArgumentsPreserveShellCharactersAsData() throws {
        let root = URL(fileURLWithPath: "/tmp/MailPort $(touch bad); 'quoted'", isDirectory: true)
        let compose = try GmailCompose(subject: "Hello $(touch bad); & \"hello\"")
        let plan = try BrowserLaunchPlan(account: Account(name: "$(danger)"), url: compose.url, profilesDirectory: root)
        XCTAssertEqual(plan.arguments[0], "--user-data-dir=\(plan.profileDirectory.path)")
        XCTAssertEqual(plan.arguments[3], "--app=\(compose.url.absoluteString)")
        XCTAssertEqual(plan.arguments.count, 4)
    }

    func testMailtoPreservesPlusEncodedUnicodeAndBodyNewlines() throws {
        let input = URL(string: "mailto:chris+tag@example.com?cc=team%40example.com&subject=Hello%20%26%20%E2%9C%93&body=One%0D%0ATwo%2Bthree")!
        let compose = try GmailCompose(mailto: input)
        XCTAssertEqual(compose.to, "chris+tag@example.com")
        XCTAssertEqual(compose.cc, "team@example.com")
        XCTAssertEqual(compose.subject, "Hello & ✓")
        XCTAssertEqual(compose.body, "One\r\nTwo+three")
        let components = try XCTUnwrap(URLComponents(url: compose.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "mail.google.com")
        XCTAssertTrue(compose.url.absoluteString.contains("chris%2Btag"))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "su" })?.value, compose.subject)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value, compose.body)
    }

    func testMailtoDuplicateRecipientHeadersMergeAndSubjectUsesFirst() throws {
        let compose = try GmailCompose(mailto: URL(string: "mailto:first@example.com?to=second@example.com&cc=a@example.com&cc=b@example.com&subject=First&subject=Second&redirect=https://evil.test")!)
        XCTAssertEqual(compose.to, "first@example.com,second@example.com")
        XCTAssertEqual(compose.cc, "a@example.com,b@example.com")
        XCTAssertEqual(compose.subject, "First")
        XCTAssertFalse(compose.url.absoluteString.contains("evil"))
    }

    func testMailtoRejectsHeaderInjectionButAllowsBodyLines() throws {
        for address in [
            "mailto:person@example.com%0D%0ABcc:other@example.com",
            "mailto:person@example.com?subject=Hello%0ABcc:other@example.com",
            "mailto:person@example.com?cc=other@example.com%0D%0ASubject:bad",
            "https://example.com/", "mailto://example.com/person", "mailto:a@example.com#unexpected"
        ] {
            XCTAssertThrowsError(try GmailCompose(mailto: URL(string: address)!), address)
        }
        XCTAssertEqual(try GmailCompose(mailto: URL(string: "mailto:?body=First%0ASecond")!).body, "First\nSecond")
    }

    func testAccountValidationTrimsAndAllowsOptionalEmail() throws {
        XCTAssertEqual(try Account(name: "  Personal \n", email: " chris@example.com ").validated().name, "Personal")
        XCTAssertEqual(try Account(name: "Work", email: "").validated().email, "")
        XCTAssertThrowsError(try Account(name: " \n ").validated())
        XCTAssertThrowsError(try Account(name: "Personal", email: "invalid").validated())
        XCTAssertThrowsError(try Account(name: "Personal", email: "a@example.com\nb@example.com").validated())
    }

    func testPersistenceRoundTripAndMissingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        XCTAssertEqual(try store.load(), [])
        let accounts = [Account(name: "Personal", email: "chris@example.com", color: .teal), Account(name: "Work", color: .orange)]
        try store.save(accounts)
        XCTAssertEqual(try store.load(), accounts)
        try store.save([accounts[1]])
        XCTAssertEqual(try store.load(), [accounts[1]])
    }

    func testCorruptPersistenceIsReportedAndPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AccountStore(directory: directory)
        let corrupt = Data("this is not valid JSON".utf8)
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    func testDuplicateIdentifiersAreRejectedBeforeSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        let account = Account(name: "Personal")
        XCTAssertThrowsError(try store.save([account, account]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
