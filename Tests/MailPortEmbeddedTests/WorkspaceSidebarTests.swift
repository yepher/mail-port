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

final class WorkspaceSidebarTests: XCTestCase {
    private let work = Account(name: "Disposable work")
    private let personal = Account(name: "Disposable personal")
    private let search = URL(string: "https://mail.google.com/mail/u/0/#search/atlas")!

    @MainActor private func fixture(pins: [WorkspacePin] = []) async throws -> (EmbeddedWorkspace, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        try AccountStore(directory: directory).save([work, personal])
        let domain = "com.chriswilson.mailport.testing." + AppSecurity.testingSuffix(for: directory)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        // Empty tabs prevent network activity: only these fake account labels are loaded.
        preferences.set(try JSONEncoder().encode([WorkspaceTab]()), forKey: "openTabs")
        preferences.set(try JSONEncoder().encode(pins), forKey: "pins")
        let engine = PINLockEngine(store: FixturePINStore())
        let model = EmbeddedWorkspace(testingDirectory: directory, securityEngine: engine)
        for _ in 0..<200 where model.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        addTeardownBlock { @MainActor in
            UserDefaults.standard.removePersistentDomain(forName: domain)
            for id in [self.work.id, self.personal.id] { try? await LocalDataReset.eraseWebsiteData(id: id) }
        }
        return (model, directory, preferences)
    }

    @MainActor func testYouTubeOptionsAreOptInPersistAndClearWhileLocked() async throws {
        let (model, directory, preferences) = try await fixture()
        XCTAssertFalse(model.skipsYouTubeAds)
        XCTAssertFalse(model.allowsYouTubeDownloads)
        model.setSkipsYouTubeAds(true)
        model.setAllowsYouTubeDownloads(true)
        XCTAssertTrue(preferences.bool(forKey: "youtubeAutoSkipAds"))
        XCTAssertTrue(preferences.bool(forKey: "youtubeMediaDownloads"))
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(reopened.skipsYouTubeAds)
        XCTAssertTrue(reopened.allowsYouTubeDownloads)
        let enabled = await model.security.enable(pin: "628493")
        XCTAssertTrue(enabled)
        model.security.lock()
        XCTAssertFalse(model.skipsYouTubeAds)
        XCTAssertFalse(model.allowsYouTubeDownloads)
        model.setSkipsYouTubeAds(true)
        model.setAllowsYouTubeDownloads(true)
        XCTAssertFalse(model.skipsYouTubeAds)
        XCTAssertFalse(model.allowsYouTubeDownloads)
    }

    @MainActor func testWebViewHostResizesAndAllowsFullscreenReparenting() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let host = WebViewHost(webView: webView)
        host.setFrameSize(NSSize(width: 1000, height: 700))
        XCTAssertEqual(webView.frame.size, host.bounds.size)
        XCTAssertTrue(webView.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(host.constraints.isEmpty)
        let fullscreenHost = NSView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        webView.removeFromSuperview()
        fullscreenHost.addSubview(webView)
        webView.frame = fullscreenHost.bounds
        host.setFrameSize(.zero)
        XCTAssertEqual(webView.frame.size, fullscreenHost.bounds.size)
        webView.removeFromSuperview()
        host.setFrameSize(NSSize(width: 1000, height: 700))
        host.addSubview(webView)
        webView.frame = host.bounds
        XCTAssertEqual(webView.frame.size, host.bounds.size)
    }

    @MainActor private func storeExists(_ id: UUID) async -> Bool {
        await LocalDataReset.allWebsiteIdentifiers().contains(id)
    }

    @MainActor func testLoadFiltersPinsAndLockClearsThem() async throws {
        let kept = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Atlas", url: search))
        let orphan = try XCTUnwrap(WorkspacePin(accountID: UUID(), service: .gmail, name: "Gone", url: search))
        let (model, _, _) = try await fixture(pins: [kept, orphan])
        XCTAssertEqual(model.pins, [kept])
        let enabled = await model.security.enable(pin: "628493")
        XCTAssertTrue(enabled)
        model.security.lock()
        XCTAssertTrue(model.pins.isEmpty)
        XCTAssertTrue(model.accounts.isEmpty)
    }

    @MainActor func testShortcutHintsDefaultOnAndTheChoiceIsSaved() async throws {
        let (model, directory, preferences) = try await fixture()
        let tab = WorkspaceTab(accountID: work.id, service: .gmail)
        XCTAssertTrue(model.showsShortcutHints)
        XCTAssertNil(preferences.object(forKey: "showsShortcutHints"), "An untouched default must not be stored")
        XCTAssertNil(model.shortcutNumber(for: tab), "A tab that isn't open has no shortcut")
        model.setShowsShortcutHints(false)
        XCTAssertFalse(model.showsShortcutHints)
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(reopened.showsShortcutHints)
    }

    @MainActor func testSignInStatusClearsAndIsDroppedWithTheAccountAndOnLock() async throws {
        let (model, _, _) = try await fixture()
        model.updateSignIn(true, for: work.id)
        model.updateSignIn(true, for: personal.id)
        XCTAssertEqual(model.accountsNeedingSignIn, [work.id, personal.id])
        model.updateSignIn(false, for: personal.id)
        XCTAssertEqual(model.accountsNeedingSignIn, [work.id])
        model.removeAccount(work)
        XCTAssertTrue(model.accountsNeedingSignIn.isEmpty)
        model.updateSignIn(true, for: personal.id)
        let enabled = await model.security.enable(pin: "628493")
        XCTAssertTrue(enabled)
        model.security.lock()
        XCTAssertTrue(model.accountsNeedingSignIn.isEmpty)
    }

    @MainActor func testZoomIsSavedPerServiceAndBadSavedValuesAreDropped() async throws {
        let (model, directory, preferences) = try await fixture()
        model.setZoom(1.25, for: .gmail)
        model.setZoom(40, for: .calendar)
        XCTAssertEqual(model.serviceZoom, [.gmail: 1.25])
        preferences.set(["gmail": 1.5, "calendar": 99.0, "unknown": 1.25], forKey: "serviceZoom")
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(reopened.serviceZoom, [.gmail: 1.5])
    }

    @MainActor func testDefaultMailAccountPersistsAndClearsWithTheAccount() async throws {
        let (model, directory, preferences) = try await fixture()
        model.setDefaultMailAccount(work.id)
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(reopened.defaultMailAccountID, work.id)
        model.removeAccount(work)
        XCTAssertNil(model.defaultMailAccountID)
        XCTAssertNil(preferences.string(forKey: "defaultMailAccount"))
        model.setDefaultMailAccount(personal.id)
        preferences.set(UUID().uuidString, forKey: "defaultMailAccount")
        let stale = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where stale.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNil(stale.defaultMailAccountID, "A default pointing at a missing account is ignored")
    }

    @MainActor private func unread(_ count: Int) throws -> TabActivity {
        try XCTUnwrap(TabActivity(message: ["kind": "unread", "count": count], service: .gmail))
    }

    @MainActor func testDockBadgeCountsChosenAccountsAndClearsWhenLocked() async throws {
        let (model, directory, _) = try await fixture()
        model.recordActivity(try unread(5), for: WorkspaceTab(accountID: work.id, service: .gmail))
        model.recordActivity(try unread(2), for: WorkspaceTab(accountID: personal.id, service: .gmail))
        XCTAssertEqual(model.dockBadgeLabel(), "7")
        model.setCountsInDockBadge(false, for: work)
        XCTAssertEqual(model.dockBadgeLabel(), "2")
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(reopened.dockBadgeExcluded, [work.id])
        let enabled = await model.security.enable(pin: "628493")
        XCTAssertTrue(enabled)
        model.security.lock()
        XCTAssertNil(model.dockBadgeLabel(), "A locked app must not show an unread total")
    }

    @MainActor func testNotificationChoicesAreSavedPerAccountAndDroppedWithIt() async throws {
        let (model, directory, _) = try await fixture()
        let until = Date().addingTimeInterval(3600)
        model.muteNotifications(for: work, until: until)
        model.setHidesPreviews(true, for: personal)
        let reopened = EmbeddedWorkspace(testingDirectory: directory, securityEngine: PINLockEngine(store: FixturePINStore()))
        for _ in 0..<200 where reopened.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(reopened.notificationSettings(for: work).isMuted(at: Date()))
        XCTAssertFalse(reopened.notificationSettings(for: personal).isMuted(at: Date()))
        XCTAssertTrue(reopened.notificationSettings(for: personal).hidesPreviews)
        model.muteNotifications(for: work, until: nil)
        XCTAssertFalse(model.notificationSettings(for: work).isMuted(at: Date()))
        model.removeAccount(personal)
        XCTAssertNil(model.notificationSettings[personal.id])
    }

    @MainActor func testMovedPinsKeepTheirOrderInSavedPreferences() async throws {
        let first = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "First", url: search))
        let second = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Second", url: search))
        let (model, _, preferences) = try await fixture(pins: [first, second])
        model.movePin(second, over: first)
        XCTAssertEqual(model.pins, [second, first])
        let saved = try JSONDecoder().decode([WorkspacePin].self, from: try XCTUnwrap(preferences.data(forKey: "pins")))
        XCTAssertEqual(saved, [second, first])
    }

    @MainActor func testPinsCannotMoveWhileLocked() async throws {
        let first = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "First", url: search))
        let second = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Second", url: search))
        let (model, _, preferences) = try await fixture(pins: [first, second])
        let enabled = await model.security.enable(pin: "628493")
        XCTAssertTrue(enabled)
        model.security.lock()
        model.movePin(second, over: first)
        let saved = try JSONDecoder().decode([WorkspacePin].self, from: try XCTUnwrap(preferences.data(forKey: "pins")))
        XCTAssertEqual(saved, [first, second])
    }

    @MainActor func testRemovingAnAccountKeepsItsWebsiteDataButDropsItsPins() async throws {
        let pin = try XCTUnwrap(WorkspacePin(accountID: work.id, service: .gmail, name: "Atlas", url: search))
        let (model, directory, _) = try await fixture(pins: [pin])
        _ = WKWebsiteDataStore(forIdentifier: work.id)
        model.removeAccount(work)
        XCTAssertEqual(model.accounts, [personal])
        XCTAssertTrue(model.pins.isEmpty)
        XCTAssertEqual(try AccountStore(directory: directory).load(), [personal])
        try await LocalDataReset.eraseWebsiteData(id: work.id)
    }

    @MainActor private func cookies(in id: UUID) async -> [String] {
        await WKWebsiteDataStore(forIdentifier: id).httpCookieStore.allCookies().map(\.name)
    }

    @MainActor private func seedCookie(in store: WKWebsiteDataStore) async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "session", .value: "fixture",
            .expires: Date().addingTimeInterval(3600)]))
        await store.httpCookieStore.setCookie(cookie)
    }

    @MainActor func testSignOutDeletesOnlyThatAccountsStoreAndEntry() async throws {
        let (model, directory, _) = try await fixture()
        let personalData = WKWebsiteDataStore(forIdentifier: personal.id)
        try await seedCookie(in: personalData)
        var workData: WKWebsiteDataStore? = WKWebsiteDataStore(forIdentifier: work.id)
        try await seedCookie(in: try XCTUnwrap(workData))
        let seeded = await cookies(in: work.id)
        XCTAssertEqual(seeded, ["session"])
        workData = nil
        await model.signOutAndRemoveAccount(work)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.accounts, [personal])
        XCTAssertEqual(try AccountStore(directory: directory).load(), [personal])
        let workRemains = await storeExists(work.id)
        XCTAssertFalse(workRemains)
        let remaining = await cookies(in: personal.id)
        XCTAssertEqual(remaining, ["session"])
    }

    @MainActor func testFailedSignOutKeepsTheAccountSoItCanBeRetried() async throws {
        let (model, directory, _) = try await fixture()
        var inUse: WKWebsiteDataStore? = WKWebsiteDataStore(forIdentifier: work.id)
        try await seedCookie(in: try XCTUnwrap(inUse))
        await model.signOutAndRemoveAccount(work)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.accounts, [work, personal])
        XCTAssertEqual(try AccountStore(directory: directory).load(), [work, personal])
        inUse = nil
        model.errorMessage = nil
        await model.signOutAndRemoveAccount(work)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.accounts, [personal])
    }

    @MainActor func testDebugBuildsCannotSelectTheRealProfile() {
        let support = URL(fileURLWithPath: "/tmp/support")
        let fallback = "/tmp/support/MailPortSecurityTest-securityqa"
        XCTAssertEqual(EmbeddedWorkspace.debugDataDirectory(support: support, requested: nil, environment: nil), fallback)
        XCTAssertEqual(EmbeddedWorkspace.debugDataDirectory(support: support, requested: "/tmp/support/MailPortPreview", environment: nil), fallback)
        XCTAssertEqual(EmbeddedWorkspace.debugDataDirectory(support: support, requested: "/tmp/MailPortSecurityTest-a", environment: nil), "/tmp/MailPortSecurityTest-a")
    }

    #if !SWIFT_PACKAGE
    func testXcodeHostUsesTheDevelopmentIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.chriswilson.mailport.embedded.securityqa")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "MailPort Dev")
    }
    #endif

    @MainActor func testLayoutChoiceIsSavedInTheProfilePreferences() async throws {
        let (model, _, preferences) = try await fixture()
        XCTAssertEqual(model.layout, .sidebar)
        model.layout = .tabBar
        XCTAssertEqual(preferences.string(forKey: "workspaceLayout"), "tabBar")
    }
}
