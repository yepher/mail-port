import Foundation
import WebKit

public enum LocalDataReset {
    @MainActor public static func allWebsiteIdentifiers() async -> [UUID] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { continuation.resume(returning: $0) }
        }
    }

    @MainActor public static func erase(directory: URL, preferenceDomain: String,
        websiteIdentifiers: [UUID], includeDefaultStore: Bool = true) async throws {
        // Never allow a reset plan to target a home directory or another app's preferences.
        let name = directory.standardizedFileURL.lastPathComponent
        guard directory.isFileURL,
              name == "MailPortPreview" || name.hasPrefix("MailPortSecurityTest-"),
              preferenceDomain.hasPrefix("com.chriswilson.mailport.") else { throw PINLockError.invalidState }
        if includeDefaultStore {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard preferenceDomain == Bundle.main.bundleIdentifier,
                  directory.standardizedFileURL == support?.appendingPathComponent("MailPortPreview", isDirectory: true).standardizedFileURL else {
                throw PINLockError.invalidState
            }
        }
        for id in Set(websiteIdentifiers) {
            await clearStore(id: id)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                WKWebsiteDataStore.remove(forIdentifier: id) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        if includeDefaultStore {
            await clearStore(id: nil)
            if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let ownedCache = caches.appendingPathComponent(preferenceDomain, isDirectory: true)
                if FileManager.default.fileExists(atPath: ownedCache.path) { try FileManager.default.removeItem(at: ownedCache) }
            }
            if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                let savedState = library.appendingPathComponent("Saved Application State", isDirectory: true)
                    .appendingPathComponent(preferenceDomain + ".savedState", isDirectory: true)
                if FileManager.default.fileExists(atPath: savedState.path) { try FileManager.default.removeItem(at: savedState) }
            }
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.removePersistentDomain(forName: preferenceDomain)
        URLCache.shared.removeAllCachedResponses()
    }

    @MainActor private static func clearStore(id: UUID?) async {
        let store = id.map(WKWebsiteDataStore.init(forIdentifier:)) ?? .default()
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() }
        }
    }
}
