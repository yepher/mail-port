import AppKit
import Combine
import CryptoKit
import MailPortSecurity

@MainActor
final class AppSecurity: NSObject, ObservableObject {
    @Published private(set) var checking = true
    @Published private(set) var enabled = false
    @Published private(set) var isLocked = false
    @Published private(set) var erasing = false
    @Published private(set) var busy = false
    @Published private(set) var failures = 0
    @Published private(set) var unavailable = false
    @Published private(set) var error: String?
    @Published private(set) var didReset = false
    var blocksAccess: Bool { checking || isLocked || erasing || unavailable }
    var onLock: (() -> Void)?
    var onUnlock: (() -> Void)?
    var onErase: (() async throws -> Void)?
    private let engine: PINLockEngine
    private let preferences: UserDefaults
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    static func keychainService(testingDirectory: URL?) -> String {
        guard let testingDirectory else { return "com.chriswilson.mailport.applock.v1" }
        return "com.chriswilson.mailport.applock.testing.\(testingSuffix(for: testingDirectory))"
    }
    static func testingSuffix(for directory: URL) -> String {
        SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(preferences: UserDefaults, testingDirectory: URL?, engine: PINLockEngine? = nil) {
        self.preferences = preferences
        self.engine = engine ?? PINLockEngine(store: KeychainPINStateStore(service: Self.keychainService(testingDirectory: testingDirectory)))
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
    }

    func start() { Task { await reload() } }

    func reload() async {
        checking = true
        do {
            let state = try await engine.state(requireExisting: preferences.bool(forKey: "pinLockEnabled"))
            enabled = state.enabled
            failures = state.failures
            unavailable = false
            error = nil
            isLocked = state.enabled
            checking = false
            preferences.set(enabled, forKey: "pinLockEnabled")
            if state.resetPending { await erase() }
            else if enabled { onLock?() }
            else { onUnlock?() }
        } catch { failClosed(error) }
    }

    func lock() {
        generation += 1
        guard enabled, !erasing else { return }
        isLocked = true
        onLock?()
    }

    func enable(pin: String) async -> Bool {
        guard !blocksAccess, !busy, !enabled else { return false }
        busy = true; error = nil
        let startGeneration = generation
        defer { busy = false }
        do {
            try await engine.enable(pin: pin)
            preferences.set(true, forKey: "pinLockEnabled")
            enabled = true; failures = 0
            if generation != startGeneration { isLocked = true; onLock?() }
            return true
        } catch { failClosed(error); return false }
    }

    func unlock(pin: String) async {
        guard isLocked, !busy, !checking, !erasing, !unavailable else { return }
        busy = true; error = nil
        let startGeneration = generation
        defer { busy = false }
        do {
            let result = try await engine.verify(pin)
            failures = try await engine.state(requireExisting: true).failures
            switch result {
            case .accepted:
                guard generation == startGeneration else { return }
                isLocked = false
                onUnlock?()
            case .rejected(let remaining): error = "Incorrect PIN. \(remaining) \(remaining == 1 ? "attempt remains" : "attempts remain") before local data is erased."
            case .resetRequired: await erase()
            }
        } catch { failClosed(error) }
    }

    func disable(pin: String) async -> Bool {
        guard !blocksAccess, !busy, enabled else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await engine.disable(pin: pin)
            failures = try await engine.state(requireExisting: true).failures
            switch result {
            case .accepted:
                preferences.set(false, forKey: "pinLockEnabled")
                enabled = false
                let wasLocked = isLocked
                isLocked = false
                if wasLocked { onUnlock?() }
                return true
            case .rejected(let remaining): error = "Incorrect PIN. \(remaining) attempts remain before local data is erased."
            case .resetRequired: await erase()
            }
        } catch { failClosed(error) }
        return false
    }

    func retryErase() { guard erasing, !busy else { return }; Task { busy = true; await erase(); busy = false } }

    private func erase() async {
        let wasBusy = busy
        busy = true
        defer { busy = wasBusy }
        isLocked = true; erasing = true; error = nil
        onLock?()
        do {
            guard let onErase else { throw PINLockError.invalidState }
            try await onErase()
            try await engine.finishReset()
            preferences.set(false, forKey: "pinLockEnabled")
            enabled = false; failures = 0; isLocked = false; erasing = false
            didReset = true
            onUnlock?()
        } catch {
            // The persisted reset-pending record remains authoritative. Neither
            // a correct PIN nor an app restart can skip unfinished cleanup.
            self.error = "Local data could not be fully cleared. MailPort remains locked. \(error.localizedDescription)"
        }
    }

    private func failClosed(_ error: Error) {
        isLocked = true; checking = false; unavailable = true
        self.error = error.localizedDescription
        onLock?()
    }
}
