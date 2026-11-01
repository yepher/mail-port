import AppKit
import Foundation
import XCTest
import MailPortCore
import MailPortSecurity
@testable import MailPortEmbedded

private final class FixturePINStore: PINStateStore, @unchecked Sendable {
    var value: PINLockState?
    func read() throws -> PINLockState? { value }
    func write(_ state: PINLockState) throws { value = state }
}

final class AppSecurityTests: XCTestCase {
    @MainActor private func fixture() async throws -> (EmbeddedWorkspace, PINLockEngine, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        let account = Account(name: "Disposable security test")
        try AccountStore(directory: directory).save([account])
        let domain = "com.chriswilson.mailport.testing." + AppSecurity.testingSuffix(for: directory)
        let prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        // Empty tabs prevent network activity: only this fake account label is loaded.
        prefs.set(try JSONEncoder().encode([WorkspaceTab]()), forKey: "openTabs")
        let engine = PINLockEngine(store: FixturePINStore())
        try await engine.enable(pin: "628493")
        let model = EmbeddedWorkspace(testingDirectory: directory, securityEngine: engine)
        model.security.attemptDelay = { _ in 0 }
        for _ in 0..<200 where model.security.checking { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.security.checking)
        return (model, engine, directory)
    }

    @MainActor func testLaunchSleepWakeAndCommandsStayBehindThePIN() async throws {
        let (model, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        XCTAssertTrue(model.security.blocksAccess)
        XCTAssertTrue(model.accounts.isEmpty)
        model.addAccount()
        model.select(WorkspaceTab(accountID: UUID(), service: .gmail))
        model.receive(URL(string: "mailto:test@example.org")!)
        XCTAssertFalse(model.showingAccountEditor)
        XCTAssertNil(model.currentBrowser)
        XCTAssertNil(model.pendingCompose)
        await model.security.unlock(pin: "628493")
        XCTAssertFalse(model.security.blocksAccess)
        XCTAssertEqual(model.accounts.count, 1)
        XCTAssertNotNil(model.pendingCompose)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        XCTAssertTrue(model.security.blocksAccess)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertEqual(MailPortNotifications.shared.permission, "default")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        XCTAssertTrue(model.security.blocksAccess)
        await model.security.unlock(pin: "628493")
        XCTAssertEqual(model.accounts.count, 1)
        XCTAssertFalse(model.security.blocksAccess)
    }

    @MainActor func testTenthFailureResetsTheIsolatedWorkspaceAndClearsPINState() async throws {
        let (model, engine, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        for _ in 0..<9 { await model.security.unlock(pin: "000000") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("accounts.json").path))
        XCTAssertEqual(model.security.failures, 9)
        await model.security.unlock(pin: "000000")
        XCTAssertTrue(model.security.didReset)
        XCTAssertFalse(model.security.blocksAccess)
        XCTAssertFalse(model.security.enabled)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertTrue(model.tabs.isEmpty)
        XCTAssertNil(model.currentBrowser)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let state = try await engine.state()
        XCTAssertEqual(state, .disabled)
    }

    @MainActor func testInterruptedCleanupRemainsLockedAndResumesBeforeUnlock() async throws {
        let (model, engine, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        let original = model.security.onErase
        model.security.onErase = { throw PINLockError.unavailable }
        for _ in 0..<10 { await model.security.unlock(pin: "000000") }
        XCTAssertTrue(model.security.blocksAccess)
        XCTAssertTrue(model.security.erasing)
        let pending = try await engine.state()
        XCTAssertTrue(pending.resetPending)
        await model.security.unlock(pin: "628493")
        XCTAssertTrue(model.security.blocksAccess)
        model.security.onErase = original
        await model.security.reload()
        XCTAssertTrue(model.security.didReset)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertFalse(model.security.blocksAccess)
    }

    @MainActor func testSleepDuringPINVerificationCannotUnlockAfterWake() async throws {
        let (model, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        var finished = false
        let attempt = Task { @MainActor in await model.security.unlock(pin: "628493"); finished = true }
        while !model.security.busy && !finished { await Task.yield() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        await attempt.value
        XCTAssertTrue(model.security.blocksAccess)
        XCTAssertTrue(model.accounts.isEmpty)
        await model.security.unlock(pin: "628493")
        XCTAssertFalse(model.security.blocksAccess)
    }

    @MainActor func testWaitAfterRepeatedFailuresBlocksAttemptsWithoutSpendingThem() async throws {
        let (model, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        model.security.attemptDelay = { $0 >= 2 ? 60 : 0 }
        await model.security.unlock(pin: "000000")
        await model.security.unlock(pin: "000000")
        XCTAssertEqual(model.security.failures, 2)
        XCTAssertNotNil(model.security.retryAfter)
        await model.security.unlock(pin: "000000")
        XCTAssertEqual(model.security.failures, 2)
        await model.security.unlock(pin: "628493")
        XCTAssertTrue(model.security.isLocked, "During the wait no attempt is checked, even the correct PIN")
    }

    @MainActor func testScreenLockAndIdleFollowTheirSettings() async throws {
        let (model, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        await model.security.unlock(pin: "628493")
        model.security.setLocksWithScreen(false)
        model.security.screenDidLock()
        XCTAssertFalse(model.security.isLocked)
        model.security.setLocksWithScreen(true)
        model.security.screenDidLock()
        XCTAssertTrue(model.security.isLocked)
        await model.security.unlock(pin: "628493")
        model.security.idleSeconds = { 3600 }
        model.security.lockIfIdle()
        XCTAssertFalse(model.security.isLocked, "Idle locking is off until chosen")
        model.security.setAutoLockMinutes(15)
        model.security.idleSeconds = { 60 }
        model.security.lockIfIdle()
        XCTAssertFalse(model.security.isLocked)
        model.security.idleSeconds = { 15 * 60 }
        model.security.lockIfIdle()
        XCTAssertTrue(model.security.isLocked)
    }

    @MainActor func testConcurrentSubmissionsCountAsOnlyOneAttempt() async throws {
        let (model, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults.standard.removePersistentDomain(forName: model.preferenceDomain) }
        var finished = false
        let attempt = Task { @MainActor in await model.security.unlock(pin: "000000"); finished = true }
        while !model.security.busy && !finished { await Task.yield() }
        if !finished { await model.security.unlock(pin: "000000") }
        await attempt.value
        XCTAssertEqual(model.security.failures, 1)
    }
}
