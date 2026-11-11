import Foundation
import XCTest
import WebKit
import UIKit
import MailPortCore
@testable import MailPortMobile

final class MobileWorkspaceTests: XCTestCase {
    @MainActor private func fixture() throws -> (MobileWorkspace, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-" + UUID().uuidString)
        let domain = "MailPortSecurityTest-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        let workspace = MobileWorkspace(directory: directory, preferences: preferences)
        workspace.loadsPages = false
        addTeardownBlock {
            preferences.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        return (workspace, directory, preferences)
    }

    @MainActor func testYouTubeAdSkipIsOptInPersistsAndUpdatesExistingPages() throws {
        let (workspace, directory, preferences) = try fixture()
        XCTAssertFalse(workspace.skipsYouTubeAds)
        let account = Account(name: "Demo"); try workspace.save(account)
        let browser = workspace.browser(for: WorkspaceTab(accountID: account.id, service: .youtube))
        defer { browser.discard() }
        XCTAssertFalse(browser.skipsYouTubeAds)
        XCTAssertTrue(browser.webView.configuration.userContentController.userScripts.isEmpty)
        workspace.setSkipsYouTubeAds(true)
        XCTAssertTrue(browser.skipsYouTubeAds)
        let script = try XCTUnwrap(browser.webView.configuration.userContentController.userScripts.first)
        XCTAssertTrue(script.isForMainFrameOnly)
        XCTAssertTrue(MobileWorkspace(directory: directory, preferences: preferences).skipsYouTubeAds)
        workspace.setSkipsYouTubeAds(false)
        XCTAssertFalse(browser.skipsYouTubeAds)
        XCTAssertTrue(browser.webView.configuration.userContentController.userScripts.isEmpty)
        XCTAssertFalse(preferences.bool(forKey: "youtubeAutoSkipAds"))
    }

    @MainActor func testMobileAdSkipOnlyActivatesVisibleSkipControlsAndStopsWhenDisabled() async throws {
        let browser = MobileBrowser(tab: WorkspaceTab(accountID: UUID(), service: .youtube),
            store: .nonPersistent(), loadsInitialPage: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let controller = UIViewController()
        window.rootViewController = controller
        browser.webView.frame = window.bounds
        controller.view.addSubview(browser.webView)
        window.makeKeyAndVisible()
        defer { browser.discard(); window.isHidden = true }
        browser.webView.loadHTMLString("<html><meta name='viewport' content='width=device-width'><body><div id='movie_player'></div></body></html>", baseURL: URL(string: "https://www.youtube.com/"))
        for _ in 0..<200 where browser.webView.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        let fixture = """
        let clicks = 0;
        const player = document.getElementById('movie_player');
        for (const kind of ['hidden', 'disabled', 'ordinary', 'skip']) {
            const button = document.createElement('button');
            button.textContent = kind;
            button.className = kind === 'ordinary' ? 'other' : 'ytp-skip-ad-button';
            button.hidden = kind === 'hidden'; button.disabled = kind === 'disabled';
            button.onclick = () => { document.body.dataset.clicked = kind; document.body.dataset.clicks = String(++clicks); };
            player.append(button);
        }
        """
        _ = try await browser.webView.callAsyncJavaScript(fixture, contentWorld: .page)
        let initial = try await browser.webView.callAsyncJavaScript("return document.body.dataset.clicked", contentWorld: .page) as? String
        XCTAssertNil(initial)
        browser.skipsYouTubeAds = true
        var clicked: String?
        for _ in 0..<100 {
            clicked = try await browser.webView.callAsyncJavaScript("return document.body.dataset.clicked", contentWorld: .page) as? String
            if clicked != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(clicked, "skip")
        browser.skipsYouTubeAds = false
        // Evaluate in the same world to wait until disabling has cleared its timer.
        _ = try await browser.webView.callAsyncJavaScript("return true", contentWorld: .defaultClient)
        let before = try await browser.webView.callAsyncJavaScript("return document.body.dataset.clicks", contentWorld: .page) as? String
        try await Task.sleep(for: .milliseconds(700))
        let after = try await browser.webView.callAsyncJavaScript("return document.body.dataset.clicks", contentWorld: .page) as? String
        XCTAssertEqual(before, after)
    }

    @MainActor func testAccountProfilesShareOnlyTheirOwnSignIn() throws {
        let (workspace, _, _) = try fixture()
        let work = Account(name: "Work", email: "work@example.org")
        let personal = Account(name: "Personal", email: "personal@example.org")
        try workspace.save(work); try workspace.save(personal)
        let mail = workspace.browser(for: WorkspaceTab(accountID: work.id, service: .gmail))
        let calendar = workspace.browser(for: WorkspaceTab(accountID: work.id, service: .calendar))
        let other = workspace.browser(for: WorkspaceTab(accountID: personal.id, service: .gmail))
        XCTAssertTrue(mail.webView.configuration.websiteDataStore === calendar.webView.configuration.websiteDataStore)
        XCTAssertFalse(mail.webView.configuration.websiteDataStore === other.webView.configuration.websiteDataStore)
        XCTAssertEqual(mail.webView.configuration.websiteDataStore.identifier, work.id)
        for browser in [mail, calendar, other] { browser.discard() }
        addTeardownBlock { @MainActor in
            try? await WKWebsiteDataStore.remove(forIdentifier: work.id)
            try? await WKWebsiteDataStore.remove(forIdentifier: personal.id)
        }
    }

    @MainActor func testServicesAndPinsPersistAndSelectionSurvivesReopening() throws {
        let (workspace, directory, preferences) = try fixture()
        let work = Account(name: "Work")
        try workspace.save(work)
        workspace.open(.youtube, in: work)
        let tab = try XCTUnwrap(workspace.selection)
        XCTAssertEqual(tab.service, .youtube)
        let pin = try XCTUnwrap(workspace.pin(URL(string: "https://www.youtube.com/watch?v=IHBNCtkQuGY")!, named: "Watch later", in: tab))
        let reopened = MobileWorkspace(directory: directory, preferences: preferences)
        reopened.loadsPages = false
        XCTAssertEqual(reopened.selection, tab)
        XCTAssertEqual(reopened.pins, [pin])
        XCTAssertFalse(workspace.canClose(WorkspaceTab(accountID: work.id, service: .gmail)))
        workspace.close(tab)
        XCTAssertFalse(workspace.tabs.contains(tab))
    }

    @MainActor func testMemoryPressureKeepsMeetAndDiscardedPagesCannotRoute() throws {
        let (workspace, _, _) = try fixture()
        let work = Account(name: "Work"); try workspace.save(work)
        workspace.open(.meet, in: work)
        let meeting = workspace.browser(for: try XCTUnwrap(workspace.selection))
        workspace.open(.drive, in: work)
        let driveTab = try XCTUnwrap(workspace.selection)
        let drive = workspace.browser(for: driveTab)
        workspace.open(.gmail, in: work)
        workspace.releaseBackgroundPages()
        XCTAssertTrue(workspace.browser(for: WorkspaceTab(accountID: work.id, service: .meet)) === meeting)
        XCTAssertNil(drive.onOpenInService)
        XCTAssertNil(drive.webView.navigationDelegate)
        XCTAssertFalse(workspace.browser(for: driveTab) === drive)
        workspace.close(driveTab)
        meeting.discard()
    }

    @MainActor func testAccountRemovalFinishesBeforeDroppingItsSavedIdentity() async throws {
        let (workspace, directory, _) = try fixture()
        let account = Account(name: "Disposable removal")
        try workspace.save(account)
        workspace.remove(account)
        workspace.remove(account)
        XCTAssertTrue(workspace.removingAccountIDs.contains(account.id))
        for _ in 0..<200 where workspace.removingAccountIDs.contains(account.id) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(workspace.removingAccountIDs.isEmpty)
        XCTAssertTrue(workspace.accounts.isEmpty)
        XCTAssertTrue(workspace.tabs.isEmpty)
        XCTAssertTrue(try AccountStore(directory: directory).load().isEmpty)
        XCTAssertNil(workspace.errorMessage)
    }

    @MainActor func testUnreadableAccountsPreventOverwrite() throws {
        let (_, directory, preferences) = try fixture()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("accounts.json")
        let original = Data("unreadable fixture".utf8); try original.write(to: file)
        let workspace = MobileWorkspace(directory: directory, preferences: preferences)
        XCTAssertFalse(workspace.storageAvailable)
        XCTAssertThrowsError(try workspace.save(Account(name: "Replacement")))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor func testDownloadFilenamesStayInsideUniqueTemporaryFolders() throws {
        let tab = WorkspaceTab(accountID: UUID(), service: .drive)
        let browser = MobileBrowser(tab: tab, store: .nonPersistent(), loadsInitialPage: false)
        defer { browser.discard() }
        let first = try browser.makeDownloadDestination(suggestedFilename: "../../private/report.pdf")
        let second = try browser.makeDownloadDestination(suggestedFilename: "..")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        XCTAssertEqual(first.lastPathComponent, "report.pdf")
        XCTAssertEqual(second.lastPathComponent, "Download")
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    }

    @MainActor func testBlobDownloadCanBeSavedAndCleanedUp() async throws {
        let browser = MobileBrowser(tab: WorkspaceTab(accountID: UUID(), service: .drive), store: .nonPersistent(), loadsInitialPage: false)
        defer { browser.discard() }
        // Entirely local page and blob. No accounts or network access.
        browser.webView.loadHTMLString("<html><body>Download fixture</body></html>", baseURL: nil)
        for _ in 0..<100 where browser.webView.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        _ = try await browser.webView.evaluateJavaScript("""
            var a = document.createElement('a');
            a.href = URL.createObjectURL(new Blob(['fixture download'], {type:'text/plain'}));
            a.download = 'fixture.txt'; document.body.appendChild(a); a.click();
            """)
        for _ in 0..<200 where browser.savedDownloads.isEmpty && browser.downloadError == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(browser.downloadError)
        let saved = try XCTUnwrap(browser.savedDownloads.first)
        XCTAssertEqual(try String(contentsOf: saved.url, encoding: .utf8), "fixture download")
        browser.removeDownload(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.url.path))
    }

    @MainActor func testMediaPermissionDelegateIsConnectedToWebKit() {
        let browser = MobileBrowser(tab: WorkspaceTab(accountID: UUID(), service: .meet), store: .nonPersistent(), loadsInitialPage: false)
        defer { browser.discard() }
        XCTAssertTrue(browser.responds(to: NSSelectorFromString("webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:")))
    }
}
