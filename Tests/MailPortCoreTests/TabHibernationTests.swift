import XCTest
@testable import MailPortCore

final class TabHibernationTests: XCTestCase {
    private let hour: TimeInterval = 3600

    private func hibernates(_ service: GoogleService = .drive, _ edit: (inout TabHibernation.PageState) -> Void = { _ in }) -> Bool {
        var state = TabHibernation.PageState()
        edit(&state)
        return TabHibernation.shouldHibernate(service, idleFor: hour, limit: 1800, state: state)
    }

    func testOnlyIdleBackgroundPagesHibernate() {
        XCTAssertTrue(hibernates())
        XCTAssertFalse(TabHibernation.shouldHibernate(.drive, idleFor: 1799, limit: 1800, state: .init()))
    }

    func testPagesInUseNeverHibernate() {
        XCTAssertFalse(hibernates { $0.isSelected = true })
        XCTAssertFalse(hibernates { $0.isDetached = true })
        XCTAssertFalse(hibernates { $0.isPlaying = true })
        XCTAssertFalse(hibernates { $0.isCapturing = true })
        XCTAssertFalse(hibernates { $0.isDownloading = true })
        XCTAssertFalse(hibernates { $0.isLoading = true })
        XCTAssertFalse(hibernates { $0.needsSignIn = true })
    }

    func testLiveWorkAndRemindersStayLoaded() {
        XCTAssertFalse(hibernates(.meet))
        XCTAssertFalse(hibernates(.colab))
        XCTAssertFalse(hibernates(.calendar) { $0.deliversReminders = true })
        XCTAssertTrue(hibernates(.calendar))
        XCTAssertTrue(hibernates(.gmail))
    }

    func testChecksSlowDownInLowPowerMode() {
        XCTAssertEqual(TabHibernation.checkInterval(for: .gmail, lowPower: false), 300)
        XCTAssertEqual(TabHibernation.checkInterval(for: .gmail, lowPower: true), 600)
        XCTAssertEqual(TabHibernation.checkInterval(for: .calendar, lowPower: false), 900)
    }

    func testCheckIsDueOnlyAfterItsInterval() {
        let now = Date()
        XCTAssertTrue(TabHibernation.isCheckDue(lastCheck: nil, interval: 300, now: now))
        XCTAssertFalse(TabHibernation.isCheckDue(lastCheck: now.addingTimeInterval(-299), interval: 300, now: now))
        XCTAssertTrue(TabHibernation.isCheckDue(lastCheck: now.addingTimeInterval(-300), interval: 300, now: now))
    }

    func testOnlyARisingCountIsNewMail() {
        XCTAssertEqual(TabHibernation.newMessages(previous: 2, current: 5), 3)
        XCTAssertEqual(TabHibernation.newMessages(previous: 5, current: 2), 0)
        XCTAssertEqual(TabHibernation.newMessages(previous: nil, current: 5), 0, "A first count has nothing to compare with")
        XCTAssertEqual(TabHibernation.newMessages(previous: 5, current: nil), 0)
        XCTAssertEqual(TabHibernation.newMailTitle(1), "1 new message")
        XCTAssertEqual(TabHibernation.newMailTitle(3), "3 new messages")
    }

    func testHeldSampleOutlastsTheNormalFreshnessWindow() throws {
        let start = Date()
        let sample = try XCTUnwrap(TabActivity(message: ["kind": "unread", "count": 4], service: .gmail, now: start))
        let later = start.addingTimeInterval(500)
        XCTAssertFalse(sample.isFresh(at: later))
        let held = sample.lasting(900)
        XCTAssertTrue(held.isFresh(at: later))
        XCTAssertEqual(held.unreadBadge(at: later), "4")
        XCTAssertFalse(held.isFresh(at: start.addingTimeInterval(901)))
    }

    func testRecoveryOnlyRetriesFailuresTimeCanFix() {
        XCTAssertTrue(PageRecovery.isTransient(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertTrue(PageRecovery.isTransient(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        XCTAssertFalse(PageRecovery.isTransient(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
        XCTAssertFalse(PageRecovery.isTransient(domain: "WebKitErrorDomain", code: 102))
        XCTAssertEqual(PageRecovery.delay(attempt: 0), 5)
        XCTAssertEqual(PageRecovery.delay(attempt: 2), 20)
        XCTAssertEqual(PageRecovery.delay(attempt: 50), 300)
    }

    func testDownloadsAndPolicyStopsAreNotErrors() {
        XCTAssertTrue(PageRecovery.isExpected(domain: "WebKitErrorDomain", code: 102))
        XCTAssertTrue(PageRecovery.isExpected(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        XCTAssertFalse(PageRecovery.isExpected(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
    }

    func testGoogleLinksFindTheirService() throws {
        func service(_ address: String) throws -> GoogleService? { BrowserLinkRouting.service(for: try XCTUnwrap(URL(string: address))) }
        XCTAssertEqual(try service("https://meet.google.com/abc-defg-hij"), .meet)
        XCTAssertEqual(try service("https://drive.google.com/file/d/x/view"), .drive)
        XCTAssertEqual(try service("https://docs.google.com/document/d/x/edit"), .docs)
        XCTAssertEqual(try service("https://docs.google.com/spreadsheets/d/x/edit"), .sheets)
        XCTAssertEqual(try service("https://docs.google.com/presentation/d/x/edit"), .slides)
        XCTAssertEqual(try service("https://notebooklm.google.com/notebook/x"), .notebooklm)
        XCTAssertNil(try service("https://docs.google.com/forms/d/x/edit"))
        XCTAssertNil(try service("https://example.com/"))
        XCTAssertNil(try service("http://meet.google.com/abc"))
        XCTAssertNil(try service("https://user:pass@meet.google.com/abc"))
        XCTAssertNil(try service("https://meet.google.com.example.org/abc"))
    }

    func testGmailSearchStaysInsideTheSearchFragment() throws {
        XCTAssertNil(GmailSearch.url(query: "   "))
        let url = try XCTUnwrap(GmailSearch.url(query: " from:sam a/b+c "))
        XCTAssertEqual(url.host, "mail.google.com")
        XCTAssertEqual(url.fragment, "search/from:sam%20a%2Fb%2Bc")
    }

    func testSelectedTextBecomesADraftBodyOnly() throws {
        let link = try XCTUnwrap(GmailCompose.mailto(body: "a & b=c?\nline #2 +1"))
        let draft = try GmailCompose(mailto: link)
        XCTAssertEqual(draft.body, "a & b=c?\nline #2 +1")
        XCTAssertEqual(draft.to, "")
        XCTAssertEqual(draft.subject, "")
        let long = try GmailCompose(mailto: try XCTUnwrap(GmailCompose.mailto(body: String(repeating: "x", count: 9000))))
        XCTAssertEqual(long.body.count, 6000)
    }

    func testOneBadLabelKeepsTheAccountAndItsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bad = Account(name: "  ", email: "not-an-address")
        let good = Account(name: "Disposable")
        let data = try JSONEncoder().encode([bad, good])
        try data.write(to: directory.appendingPathComponent("accounts.json"))
        let loaded = try AccountStore(directory: directory).load()
        XCTAssertEqual(loaded.map(\.id), [bad.id, good.id])
        XCTAssertEqual(loaded[0].name, "Account")
        XCTAssertEqual(loaded[0].email, "")
    }
}
