import Foundation
import CommonCrypto
import Security
import CryptoKit
import Darwin

public enum PINLockError: LocalizedError {
    case invalidPIN, invalidState, alreadyEnabled, unavailable
    case keychain(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .invalidPIN: "Use exactly six digits for the PIN."
        case .invalidState: "MailPort’s PIN security state is invalid. Access remains locked."
        case .alreadyEnabled: "PIN protection is already enabled."
        case .unavailable: "MailPort’s PIN security state is unavailable. Unlock your Mac Keychain and reopen MailPort."
        case .keychain(let status): "MailPort couldn’t access its Keychain security record (\(status)). Access remains locked."
        }
    }
}

public struct PINCredential: Codable, Equatable, Sendable {
    public let salt: Data
    public let verifier: Data
    public let rounds: UInt32
    public static func isValidPIN(_ pin: String) -> Bool { pin.utf8.count == 6 && pin.utf8.allSatisfy { (48...57).contains($0) } }

    public static func create(pin: String) throws -> Self {
        guard Self.isValidPIN(pin) else { throw PINLockError.invalidPIN }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PINLockError.unavailable }
        let salt = Data(bytes)
        return Self(salt: salt, verifier: try derive(pin, salt: salt, rounds: 200_000), rounds: 200_000)
    }

    public func matches(_ pin: String) throws -> Bool {
        guard Self.isValidPIN(pin) else { return false }
        guard isValid else { throw PINLockError.invalidState }
        let candidate = try Self.derive(pin, salt: salt, rounds: rounds)
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, verifier) { difference |= a ^ b }
        return difference == 0
    }

    public var isValid: Bool { salt.count == 16 && verifier.count == 32 && rounds == 200_000 }

    private static func derive(_ pin: String, salt: Data, rounds: UInt32) throws -> Data {
        var result = Data(count: 32)
        let status = result.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                pin.withCString { password in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, pin.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.bindMemory(to: UInt8.self).baseAddress!, output.count)
                }
            }
        }
        guard status == kCCSuccess else { throw PINLockError.unavailable }
        return result
    }
}

public struct PINLockState: Codable, Equatable, Sendable {
    public var credential: PINCredential?
    public var failures: Int
    public var resetPending: Bool
    public var version = 1
    public var enabled: Bool { credential != nil }
    public static let failureLimit = 10
    public static let disabled = Self(credential: nil, failures: 0, resetPending: false)
    /// Slows repeated guesses, so the erase limit can't be reached by accident or in moments.
    public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ..<3: 0
        case 3: 5
        case 4: 15
        case 5: 30
        case 6: 60
        case 7: 120
        case 8: 300
        default: 600
        }
    }
    public init(credential: PINCredential?, failures: Int = 0, resetPending: Bool = false) {
        self.credential = credential; self.failures = failures; self.resetPending = resetPending
    }
    public func validate() throws {
        guard version == 1, (0...Self.failureLimit).contains(failures),
              credential?.isValid != false,
              enabled || (failures == 0 && !resetPending),
              resetPending == (failures == Self.failureLimit) else { throw PINLockError.invalidState }
    }
}

public protocol PINStateStore: Sendable {
    func read() throws -> PINLockState?
    func write(_ state: PINLockState) throws
    func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T
}

public extension PINStateStore {
    func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T { try operation() }
}

public struct KeychainPINStateStore: PINStateStore {
    public let service: String
    public init(service: String) { self.service = service }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pin-lock-state-v1"] }
    private func lockURL() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw PINLockError.unavailable }
        let directory = support.appendingPathComponent("MailPortPINLockState", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let digest = SHA256.hash(data: Data(service.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".lock")
    }
    public func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
        let file = try lockURL()
        let fd = Darwin.open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw PINLockError.unavailable }
        defer { Darwin.close(fd) }
        while flock(fd, LOCK_EX) != 0 { if errno != EINTR { throw PINLockError.unavailable } }
        defer { _ = flock(fd, LOCK_UN) }
        return try operation()
    }
    public func read() throws -> PINLockState? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw PINLockError.keychain(status) }
        let state = try JSONDecoder().decode(PINLockState.self, from: data)
        try state.validate()
        return state
    }
    public func write(_ state: PINLockState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecAttrSynchronizable as String] = false
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw PINLockError.keychain(added) }
        } else if status != errSecSuccess { throw PINLockError.keychain(status) }
    }
    /// Used only to remove disposable test records. Normal disable/reset writes a
    /// credential-free sentinel so an interrupted operation cannot bypass the lock.
    public func deleteTestRecord() throws {
        guard service.contains(".testing.") else { throw PINLockError.invalidState }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PINLockError.keychain(status) }
        try? FileManager.default.removeItem(at: lockURL())
    }
}

public enum PINCheckResult: Equatable, Sendable { case accepted, rejected(remaining: Int), resetRequired }

public actor PINLockEngine {
    private let store: any PINStateStore
    public init(store: any PINStateStore) { self.store = store }
    private func readState(requireExisting: Bool = false) throws -> PINLockState {
        guard let value = try store.read() else {
            if requireExisting { throw PINLockError.unavailable }
            return .disabled
        }
        try value.validate()
        return value
    }
    public func state(requireExisting: Bool = false) throws -> PINLockState {
        try store.withExclusiveAccess { try readState(requireExisting: requireExisting) }
    }
    public func enable(pin: String) throws {
        try store.withExclusiveAccess {
            let previous = try readState()
            guard !previous.enabled else { throw PINLockError.alreadyEnabled }
            try store.write(PINLockState(credential: PINCredential.create(pin: pin)))
        }
    }
    private func verifyInTransaction(_ pin: String) throws -> PINCheckResult {
        var current = try readState(requireExisting: true)
        guard let credential = current.credential else { throw PINLockError.invalidState }
        if current.resetPending { return .resetRequired }
        // Something that can't be a PIN says nothing about who is typing, so it costs no attempt.
        guard PINCredential.isValidPIN(pin) else { return .rejected(remaining: PINLockState.failureLimit - current.failures) }
        if try credential.matches(pin) {
            current.failures = 0
            try store.write(current)
            return .accepted
        }
        current.failures += 1
        current.resetPending = current.failures == PINLockState.failureLimit
        try store.write(current)
        return current.resetPending ? .resetRequired : .rejected(remaining: PINLockState.failureLimit - current.failures)
    }
    public func verify(_ pin: String) throws -> PINCheckResult {
        // Hold the process-shared lock across read, verification, and persistence.
        // Multiple running copies cannot each overwrite the same failure count.
        try store.withExclusiveAccess { try verifyInTransaction(pin) }
    }
    public func disable(pin: String) throws -> PINCheckResult {
        try store.withExclusiveAccess {
            let result = try verifyInTransaction(pin)
            if result == .accepted { try store.write(.disabled) }
            return result
        }
    }
    public func finishReset() throws {
        try store.withExclusiveAccess {
            guard try readState(requireExisting: true).resetPending else { throw PINLockError.invalidState }
            try store.write(.disabled)
        }
    }
}
