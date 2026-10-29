import Foundation
import XCTest
import WebKit
@testable import MailPortSecurity

private final class MemoryPINStore: PINStateStore, @unchecked Sendable {
    var value: PINLockState?
    var failWrites = false
    func read() throws -> PINLockState? { value }
    func write(_ state: PINLockState) throws {
        if failWrites { throw PINLockError.unavailable }
        value = state
    }
}

final class PINLockTests: XCTestCase {
    func testPINUsesRandomSaltAndDoesNotStorePlaintext() throws {
        let first = try PINCredential.create(pin: "628493")
        let second = try PINCredential.create(pin: "628493")
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertTrue(try first.matches("628493"))
        XCTAssertFalse(try first.matches("628494"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains("628493"))
        for pin in ["12345", "1234567", "１２３４５６", "abcdef", " 12345"] { XCTAssertFalse(PINCredential.isValidPIN(pin)) }
    }

    func testNineFailuresDoNotEraseAndCorrectPINResetsTheConsecutiveCount() async throws {
        let store = MemoryPINStore()
        let tested = PINLockEngine(store: store)
        try await tested.enable(pin: "628493")
        for n in 1...9 {
            let result = try await tested.verify("000000")
            XCTAssertEqual(result, .rejected(remaining: 10 - n))
        }
        XCTAssertEqual(store.value?.failures, 9)
        XCTAssertFalse(store.value!.resetPending)
        let accepted = try await tested.verify("628493")
        XCTAssertEqual(accepted, .accepted)
        XCTAssertEqual(store.value?.failures, 0)
        let following = try await tested.verify("000000")
        XCTAssertEqual(following, .rejected(remaining: 9))
    }

    func testTenthFailurePersistsResetAndCannotBeBypassedByCorrectPINOrRestart() async throws {
        let store = MemoryPINStore()
        let tested = PINLockEngine(store: store)
        try await tested.enable(pin: "628493")
        for _ in 1...9 { _ = try await tested.verify("000000") }
        let tenth = try await tested.verify("000000")
        XCTAssertEqual(tenth, .resetRequired)
        XCTAssertEqual(store.value?.failures, 10)
        XCTAssertTrue(store.value!.resetPending)
        let restarted = PINLockEngine(store: store)
        let afterRestart = try await restarted.verify("628493")
        XCTAssertEqual(afterRestart, .resetRequired)
        try await restarted.finishReset()
        XCTAssertEqual(store.value, .disabled)
        XCTAssertNil(store.value?.credential)
    }

    func testFailureCountSurvivesEngineRecreationAndMissingStateFailsClosed() async throws {
        let store = MemoryPINStore()
        let tested = PINLockEngine(store: store)
        try await tested.enable(pin: "628493")
        _ = try await tested.verify("000000")
        let restarted = PINLockEngine(store: store)
        let result = try await restarted.verify("000000")
        XCTAssertEqual(result, .rejected(remaining: 8))
        store.value = nil
        do { _ = try await restarted.state(requireExisting: true); XCTFail("Missing configured state must stay locked") } catch {}
    }

    func testPersistenceFailureNeverGrantsAccess() async throws {
        let store = MemoryPINStore()
        let tested = PINLockEngine(store: store)
        try await tested.enable(pin: "628493")
        store.failWrites = true
        do { _ = try await tested.verify("628493"); XCTFail("A correct PIN must not unlock when state cannot be persisted") } catch {}
    }

    func testDisablingRequiresTheCurrentPINAndSharesTheFailureCounter() async throws {
        let store = MemoryPINStore()
        let engine = PINLockEngine(store: store)
        try await engine.enable(pin: "628493")
        let rejected = try await engine.disable(pin: "000000")
        XCTAssertEqual(rejected, .rejected(remaining: 9))
        XCTAssertTrue(store.value!.enabled)
        let disabled = try await engine.disable(pin: "628493")
        XCTAssertEqual(disabled, .accepted)
        XCTAssertEqual(store.value, .disabled)
    }

    func testInvalidStateAndUnrequestedResetAreRejected() async throws {
        var invalid = PINLockState.disabled
        invalid.failures = 11
        XCTAssertThrowsError(try invalid.validate())
        invalid = PINLockState(credential: try PINCredential.create(pin: "628493"), failures: 3, resetPending: true)
        XCTAssertThrowsError(try invalid.validate())
        let engine = PINLockEngine(store: MemoryPINStore())
        try await engine.enable(pin: "628493")
        do { try await engine.finishReset(); XCTFail("Cleanup cannot be marked complete before the threshold") } catch {}
        do { try await engine.enable(pin: "111111"); XCTFail("Cannot replace an existing PIN without verification") } catch {}
    }

    func testDisposableKeychainRecordRoundTripsAndRetainsFailures() async throws {
        let store = KeychainPINStateStore(service: "com.chriswilson.mailport.applock.testing.\(UUID().uuidString)")
        defer { try? store.deleteTestRecord() }
        let engine = PINLockEngine(store: store)
        try await engine.enable(pin: "628493")
        _ = try await engine.verify("000000")
        XCTAssertEqual(try store.read()?.failures, 1)
        let restarted = PINLockEngine(store: store)
        let result = try await restarted.verify("628493")
        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(try store.read()?.failures, 0)
    }

    @MainActor func testResetClearsOnlyIsolatedFilesPreferencesAndWebsiteCookies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        let untouched = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        let domain = "com.chriswilson.mailport.testing.\(UUID().uuidString)"
        let identifier = UUID()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: untouched, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: untouched) }
        try Data("disposable account labels".utf8).write(to: root.appendingPathComponent("accounts.json"))
        let prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        prefs.set("disposable tab history", forKey: "openTabs")
        var liveStore: WKWebsiteDataStore? = WKWebsiteDataStore(forIdentifier: identifier)
        let cookie = HTTPCookie(properties: [.domain: "example.org", .path: "/", .name: "isolatedSession", .value: "test-only", .expires: Date().addingTimeInterval(3600)])!
        await withCheckedContinuation { continuation in liveStore!.httpCookieStore.setCookie(cookie) { continuation.resume() } }
        let before: Int = await withCheckedContinuation { continuation in liveStore!.httpCookieStore.getAllCookies { continuation.resume(returning: $0.count) } }
        liveStore = nil
        XCTAssertEqual(before, 1)
        try await LocalDataReset.erase(directory: root, preferenceDomain: domain, websiteIdentifiers: [identifier], includeDefaultStore: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouched.path))
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: domain)?["openTabs"])
        let after = await testCookies(identifier: identifier)
        XCTAssertEqual(after, 0)
        // The recreated empty store is also disposable and belongs to this test runner.
        try await LocalDataReset.erase(directory: root, preferenceDomain: domain, websiteIdentifiers: [identifier], includeDefaultStore: false)
    }

    @MainActor private func testCookies(identifier: UUID) async -> Int {
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        return await withCheckedContinuation { continuation in store.httpCookieStore.getAllCookies { continuation.resume(returning: $0.count) } }
    }

    @MainActor func testUnsafeResetScopeIsRejectedBeforeDeletingAnything() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MailPortSecurityTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try await LocalDataReset.erase(directory: root, preferenceDomain: "com.apple.Safari", websiteIdentifiers: [], includeDefaultStore: false)
            XCTFail("Cannot target another application's preferences")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        do {
            try await LocalDataReset.erase(directory: root, preferenceDomain: "com.chriswilson.mailport.testing.\(UUID().uuidString)", websiteIdentifiers: [], includeDefaultStore: true)
            XCTFail("Full reset must match the current app and its production directory")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testTwoEnginesShareAnAtomicFailureCounter() async throws {
        let store = KeychainPINStateStore(service: "com.chriswilson.mailport.applock.testing.\(UUID().uuidString)")
        defer { try? store.deleteTestRecord() }
        let first = PINLockEngine(store: store), second = PINLockEngine(store: store)
        try await first.enable(pin: "628493")
        let results = try await withThrowingTaskGroup(of: PINCheckResult.self) { group in
            for index in 0..<10 { group.addTask { try await (index % 2 == 0 ? first : second).verify("000000") } }
            var values: [PINCheckResult] = []
            for try await result in group { values.append(result) }
            return values
        }
        XCTAssertEqual(results.filter { $0 == .resetRequired }.count, 1)
        XCTAssertEqual(try store.read()?.failures, 10)
        XCTAssertTrue(try store.read()!.resetPending)
    }
}
