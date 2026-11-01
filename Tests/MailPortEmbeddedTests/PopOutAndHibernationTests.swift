import AppKit
import Foundation
import WebKit
import XCTest
import MailPortCore
import MailPortSecurity
@testable import MailPortEmbedded

private final class FixturePINStore: PINStateStore, @unchecked Sendable {
    var value: PINLockState?
    func read() throws -> PINLockState? { value }
    func write(_ state: PINLockState) throws { value = state }
}

/// Every model here has page loading off, so these never reach the network.
final class PopOutAndHibernationTests: XCTestCase {
    private let work = Account(name: "Disposable work", email: "work@example.org")
    private let personal = Account(name: "Disposable personal")

    @MainActor private func fixture(pin: String? = nil, tabs: [WorkspaceTab] = []) async throws -> EmbeddedWorkspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        try AccountStore(directory: directory).save([work, personal])
        let domain = "com.chriswilson.mailport.testing." + AppSecurity.testingSuffix(for: directory)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        preferences.set(try JSONEncoder().encode(tabs), forKey: "openTabs")
        let engine = PINLockEngine(store: FixturePINStore())
        if let pin { try await engine.enable(pin: pin) }
        let model = EmbeddedWorkspace(testingDirectory: directory, securityEngine: engine)
        model.loadsPages = false
        model.security.attemptDelay = { _ in 0 }
        for _ in 0..<200 where model.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        addTeardownBlock { @MainActor in
            UserDefaults.standard.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
            for id in [self.work.id, self.personal.id] { try? await LocalDataReset.eraseWebsiteData(id: id) }
        }
        return model
    }

    private func tab(_ service: GoogleService, _ account: Account? = nil) -> WorkspaceTab {
        WorkspaceTab(accountID: (account ?? work).id, service: service)
    }

    @MainActor func testPopOutMovesTheSamePageAndReturnsItOnce() async throws {
        let model = try await fixture()
        let calendar = tab(.calendar)
        model.select(calendar)
        let webView = try XCTUnwrap(model.currentBrowser?.webView)
        let host = WebViewHost(webView: webView)
        model.toggleDetached(calendar)
        let controller = try XCTUnwrap(model.detachedViews[calendar])
        XCTAssertTrue(model.isDetached(calendar))
        XCTAssertFalse(host.subviews.contains(webView))
        XCTAssertTrue(webView.window === controller.window)
        XCTAssertFalse(controller.window!.styleMask.contains(.titled), "Pop-outs are borderless")
        XCTAssertTrue(controller.window!.canBecomeKey, "Calendar needs typing")
        model.toggleDetached(calendar)
        XCTAssertNil(model.detachedViews[calendar])
        XCTAssertNil(webView.superview)
        XCTAssertTrue(WebViewHost(webView: webView).subviews.contains(webView))
    }

    @MainActor func testKeepOnTopTogglesAndIsRememberedPerView() async throws {
        let model = try await fixture()
        let calendar = tab(.calendar)
        model.select(calendar)
        model.toggleDetached(calendar)
        let first = try XCTUnwrap(model.detachedViews[calendar])
        XCTAssertEqual(first.window?.level, .normal, "Not on top until asked")
        first.togglePin()
        XCTAssertEqual(first.window?.level, .floating)
        XCTAssertTrue(first.window?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        first.togglePin()
        XCTAssertEqual(first.window?.level, .normal)
        XCTAssertFalse(first.window?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        first.togglePin()
        model.toggleDetached(calendar)
        model.toggleDetached(calendar)
        XCTAssertEqual(model.detachedViews[calendar]?.window?.level, .floating)
        model.toggleDetached(calendar)
    }

    @MainActor func testPopOutFrameComesBackOnlyOnAConnectedScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = NSRect(x: 100, y: 100, width: 500, height: 400)
        XCTAssertEqual(DetachedViewController.placement(saved: saved, screens: [screen], fallback: screen), saved)
        let offScreen = NSRect(x: 5000, y: 100, width: 500, height: 400)
        let placed = DetachedViewController.placement(saved: offScreen, screens: [screen], fallback: screen)
        XCTAssertTrue(screen.contains(placed))
        XCTAssertTrue(screen.contains(DetachedViewController.placement(saved: nil, screens: [screen], fallback: screen)))
    }

    @MainActor func testControlsRevealAtTheTopEdgeOnly() {
        let window = NSRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(DetachedContentView.showsControls(pointer: NSPoint(x: 300, y: 596), window: window, visible: false))
        XCTAssertFalse(DetachedContentView.showsControls(pointer: NSPoint(x: 300, y: 580), window: window, visible: false), "The page's toolbar stays usable")
        XCTAssertTrue(DetachedContentView.showsControls(pointer: NSPoint(x: 300, y: 580), window: window, visible: true), "Open controls stay reachable")
        XCTAssertFalse(DetachedContentView.showsControls(pointer: NSPoint(x: 300, y: 300), window: window, visible: true))
        XCTAssertFalse(DetachedContentView.showsControls(pointer: NSPoint(x: 900, y: 596), window: window, visible: false))
    }

    @MainActor func testLockCloseAndAccountRemovalAllEndPopOuts() async throws {
        let model = try await fixture(pin: "628493")
        await model.security.unlock(pin: "628493")
        let calendar = tab(.calendar)
        model.select(calendar)
        model.toggleDetached(calendar)
        model.security.lock()
        XCTAssertTrue(model.detachedViews.isEmpty)
        await model.security.unlock(pin: "628493")
        model.select(calendar)
        model.toggleDetached(calendar)
        model.close(calendar)
        XCTAssertTrue(model.detachedViews.isEmpty)
        model.select(calendar)
        model.toggleDetached(calendar)
        await model.signOutAndRemoveAccount(work)
        XCTAssertTrue(model.detachedViews.isEmpty)
        XCTAssertFalse(model.accounts.contains(work), "A pop-out must not hold the store open and fail the sign-out")
    }

    @MainActor func testIdleBackgroundViewHibernatesAndComesBackOnSelection() async throws {
        let model = try await fixture()
        let drive = tab(.drive), mail = tab(.gmail, personal)
        model.select(drive)
        model.select(mail)
        model.runHibernation(at: Date().addingTimeInterval(20 * 60))
        XCTAssertNil(model.hibernatedTabs[drive], "Not idle long enough")
        model.runHibernation(at: Date().addingTimeInterval(31 * 60))
        XCTAssertNotNil(model.hibernatedTabs[drive])
        XCTAssertNil(model.hibernatedTabs[mail], "The selected view stays")
        XCTAssertTrue(model.tabs.contains(drive), "Hibernating isn't closing")
        model.select(drive)
        XCTAssertNil(model.hibernatedTabs[drive])
        XCTAssertNotNil(model.currentBrowser)
    }

    @MainActor func testPoppedOutAndMeetViewsNeverHibernate() async throws {
        let model = try await fixture()
        let calendar = tab(.calendar), meet = tab(.meet), mail = tab(.gmail, personal)
        model.select(calendar)
        model.toggleDetached(calendar)
        model.select(meet)
        model.select(mail)
        model.runHibernation(at: Date().addingTimeInterval(6 * 3600))
        XCTAssertNil(model.hibernatedTabs[calendar])
        XCTAssertNil(model.hibernatedTabs[meet])
        model.toggleDetached(calendar)
    }

    @MainActor func testPeriodicCheckAlertsOnlyAfterTheCountRises() async throws {
        let model = try await fixture()
        let mail = tab(.gmail), other = tab(.drive, personal)
        model.select(mail)
        model.recordActivity(TabActivity(message: ["kind": "unread", "count": 3], service: .gmail), for: mail)
        model.select(other)
        let start = Date()
        model.hibernate(mail, at: start)
        XCTAssertNotNil(model.hibernatedTabs[mail])
        model.runHibernation(at: start.addingTimeInterval(200))
        XCTAssertEqual(model.activeMailChecks, 0, "Not due yet")
        model.runHibernation(at: start.addingTimeInterval(301))
        XCTAssertEqual(model.activeMailChecks, 1)
        XCTAssertNotNil(model.hibernatedTabs[mail], "A check doesn't wake the view")
        model.hibernationCheckFinished(mail, sample: TabActivity(message: ["kind": "unread", "count": 5], service: .gmail))
        model.runHibernation(at: start.addingTimeInterval(301 + TabHibernation.checkDuration))
        XCTAssertEqual(model.activeMailChecks, 0)
        XCTAssertEqual(model.tabActivity[mail]?.unreadCount, 5)
        XCTAssertEqual(model.lastAnnouncedNewMail, 2)
    }

    @MainActor func testLockClearsHibernationState() async throws {
        let model = try await fixture(pin: "628493")
        await model.security.unlock(pin: "628493")
        let drive = tab(.drive), mail = tab(.gmail, personal)
        model.select(drive)
        model.select(mail)
        model.hibernate(drive)
        XCTAssertFalse(model.hibernatedTabs.isEmpty)
        model.security.lock()
        XCTAssertTrue(model.hibernatedTabs.isEmpty)
        XCTAssertEqual(model.activeMailChecks, 0)
    }

    @MainActor func testRestoreRefusesToReplaceAnUnreadableAccountList() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("accounts.json")
        let original = Data("{ not valid json".utf8)
        try original.write(to: file)
        let model = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where model.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.storageAvailable)
        try model.previewWorkspaceBackup(WorkspaceBackup(accounts: [Account(name: "From backup")], tabs: [], pins: []).encoded())
        model.restoreWorkspace(includeAppearance: false)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        let leftovers = await model.leftoverSignIns()
        XCTAssertTrue(leftovers.isEmpty, "Without a readable list, every sign-in would look like a leftover")
        UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain)
    }

    @MainActor func testExpectedNavigationStopsShowNoErrorButRealOnesDo() throws {
        let page = BrowserTab(account: work, service: .drive, store: .nonPersistent(), loadsInitialPage: false)
        defer { page.discardForSecurity() }
        page.webView(page.webView, didFailProvisionalNavigation: nil, withError: NSError(domain: "WebKitErrorDomain", code: 102))
        XCTAssertNil(page.errorMessage)
        XCTAssertFalse(page.needsRecovery)
        page.webView(page.webView, didFailProvisionalNavigation: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertNotNil(page.errorMessage)
        XCTAssertTrue(page.needsRecovery, "Offline pages retry by themselves")
    }

    @MainActor func testCrashedBackgroundPageSchedulesItsOwnReload() throws {
        let page = BrowserTab(account: work, service: .calendar, store: .nonPersistent(), activityOnly: true, loadsInitialPage: false)
        defer { page.discardForSecurity() }
        page.webViewWebContentProcessDidTerminate(page.webView)
        XCTAssertTrue(page.needsRecovery)
    }

    @MainActor func testGoogleLinkStaysInTheAccountOnlyFromTheFrontPage() async throws {
        let model = try await fixture()
        let calendar = tab(.calendar), other = tab(.drive, personal)
        model.select(other)
        model.select(calendar)
        let meet = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))
        let front = try XCTUnwrap(model.currentBrowser)
        XCTAssertEqual(front.onOpenInService?(.meet, meet), true)
        XCTAssertEqual(model.selection, tab(.meet))
        model.select(other)
        XCTAssertEqual(front.onOpenInService?(.gmail, meet), false, "A background page can't pull the window away")
        XCTAssertEqual(model.selection, other)
    }

    @MainActor func testRenamingReachesOpenPages() async throws {
        let model = try await fixture()
        model.select(tab(.drive))
        var renamed = work
        renamed.name = "Renamed"
        try model.saveAccount(renamed)
        XCTAssertEqual(model.currentBrowser?.account.name, "Renamed")
    }

    @MainActor func testClosingAViewKeepsItsPageUntilDownloadsFinish() async throws {
        let model = try await fixture()
        let drive = tab(.drive), mail = tab(.gmail, personal)
        model.select(mail)
        model.select(drive)
        let page = try XCTUnwrap(model.currentBrowser)
        page.markDownloadForTesting(active: true)
        model.close(drive)
        XCTAssertNotNil(page.onDownloadsFinished, "The download keeps running")
        page.markDownloadForTesting(active: false)
    }

    @MainActor func testAccountsReorderAndSurviveReopening() async throws {
        let model = try await fixture()
        model.moveAccount(work, by: 1)
        XCTAssertEqual(model.accounts.map(\.id), [personal.id, work.id])
        model.moveAccount(work, by: 1)
        XCTAssertEqual(model.accounts.map(\.id), [personal.id, work.id], "Already last")
        XCTAssertEqual(try AccountStore(directory: model.directory).load().map(\.id), [personal.id, work.id])
    }

    @MainActor func testDiagnosticsLeaveOutNamesAndAddresses() async throws {
        let model = try await fixture()
        model.select(tab(.drive))
        let report = model.diagnostics()
        XCTAssertTrue(report.contains("Accounts: 2"))
        XCTAssertFalse(report.contains(work.name))
        XCTAssertFalse(report.contains("work@example.org"))
    }
}
